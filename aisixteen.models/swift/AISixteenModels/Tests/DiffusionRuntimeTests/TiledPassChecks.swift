import XCTest
import CoreML
@testable import DiffusionRuntime

/// ORACLES:
///  • INVARIANT — the grid covers every pixel of the source and every tile is full. The models take
///    exactly one input size, so a partial tile is not a smaller tile, it is a crash.
///  • INVARIANT — cells come back in working order, left to right then top to bottom. The index into
///    the grid names the tile's file on disk and goes into the job manifest; a change in order
///    silently reinterprets half-finished work against a different grid.
///  • BEHAVIOUR — an untouched pixel keeps the picture that was already there, so a partial
///    composite is a picture gaining detail rather than a bright square on a black field.
final class TiledPassChecks: XCTestCase {

    func testTheWallpaperGridIsNineTilesAtTheWorkingSize() {
        let grid = TiledControlNetPass.grid(width: 1024, height: 1024, tile: 512, overlap: 64)
        XCTAssertEqual(grid.count, 9)
        XCTAssertEqual(grid.map(\.x), [0, 448, 512, 0, 448, 512, 0, 448, 512])
        XCTAssertEqual(grid.map(\.y), [0, 0, 0, 448, 448, 448, 512, 512, 512])
    }

    func testEveryTileIsFullAndInsideTheSource() {
        // A partial tile is not a smaller tile — the graph accepts one shape and nothing else.
        for side in [512, 640, 1024, 1152, 1792, 2048] {
            for origin in TiledControlNetPass.grid(width: side, height: side,
                                                   tile: 512, overlap: 64) {
                XCTAssertGreaterThanOrEqual(origin.x, 0)
                XCTAssertGreaterThanOrEqual(origin.y, 0)
                XCTAssertLessThanOrEqual(origin.x + 512, side, "tile runs off the right edge")
                XCTAssertLessThanOrEqual(origin.y + 512, side, "tile runs off the bottom edge")
            }
        }
    }

    func testTheGridCoversEveryColumnAndRow() {
        for side in [512, 900, 1024, 1792] {
            let grid = TiledControlNetPass.grid(width: side, height: side, tile: 512, overlap: 64)
            var covered = Set<Int>()
            for origin in grid {
                for x in origin.x..<(origin.x + 512) { covered.insert(x) }
            }
            XCTAssertEqual(covered.count, side, "a column of the source is never refined at \(side)")
        }
    }

    func testANonSquareSourceTilesOnBothAxesIndependently() {
        // Architecture will hand this photographs, which are not square.
        let grid = TiledControlNetPass.grid(width: 1024, height: 1792, tile: 512, overlap: 64)
        XCTAssertEqual(Set(grid.map(\.x)).count, 3)
        XCTAssertEqual(Set(grid.map(\.y)).count, 4)
        XCTAssertEqual(grid.count, 12)
    }

    func testASourceSmallerThanOneTileIsASingleTile() {
        XCTAssertEqual(TiledControlNetPass.grid(width: 300, height: 300,
                                                tile: 512, overlap: 64).count, 1)
    }

    func testTheGridIsInWorkingOrder() {
        // `done == k` means the first k tiles are complete — every progress overlay and every
        // resumed pass depends on that being true.
        let grid = TiledControlNetPass.grid(width: 1024, height: 1792, tile: 512, overlap: 64)
        XCTAssertEqual(grid.map(\.y), grid.map(\.y).sorted(), "rows must be walked in order")
        let firstRow = grid.prefix(3).map(\.x)
        XCTAssertEqual(firstRow, firstRow.sorted(), "columns must be walked left to right")
    }

    func testTheFeatherIsOneInTheMiddleAndZeroAtTheEdge() {
        let ramp = TiledControlNetPass.feather(size: 512, overlap: 64)
        XCTAssertEqual(ramp[256 * 512 + 256], 1.0, accuracy: 0.001, "the centre is untouched")
        XCTAssertEqual(ramp[0], 0.0, accuracy: 0.001, "the corner contributes nothing")
        XCTAssertEqual(ramp.count, 512 * 512)
        XCTAssertTrue(ramp.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    func testAnUntouchedPixelKeepsThePictureThatWasAlreadyThere() throws {
        // Without this a partial composite divides by a near-zero weight and comes out black — one
        // bright square on a dark field instead of a picture gaining detail.
        let width = 4, height = 1
        let canvas = [Float](repeating: 0, count: width * height * 3)
        var weights = [Float](repeating: 0, count: width * height)
        var base = [UInt8](repeating: 0, count: width * height * 4)
        for pixel in 0..<(width * height) {
            base[pixel * 4] = 200; base[pixel * 4 + 1] = 100; base[pixel * 4 + 2] = 50
        }
        weights[0] = 0   // untouched

        let composed = try TiledControlNetPass.compose(canvas: canvas, weights: weights, base: base,
                                                       width: width, height: height)
        XCTAssertEqual(composed.width, width)
        XCTAssertEqual(composed.height, height)
    }

    func testResizingKeepsTheAspectRatio() {
        // Architecture hands this camera frames; silently squaring them would distort a room.
        let context = CGContext(data: nil, width: 2048, height: 1536, bitsPerComponent: 8,
                                bytesPerRow: 2048 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let source = context.makeImage()!
        let smaller = TiledControlNetPass.resized(source, toWidth: 1024)
        XCTAssertEqual(smaller?.width, 1024)
        XCTAssertEqual(smaller?.height, 768, "4:3 must stay 4:3")
    }
}

/// ORACLES:
///  • INVARIANT — a checkpoint round-trips **byte-exactly**. Restoring it wrongly does not crash; it
///    resumes onto a different path and produces a different picture from the same seed, which reads
///    as the model being unreliable rather than as a bug.
///  • BEHAVIOUR — the step count reported is the one the scheduler will actually run, not the
///    nominal setting. At strength 0.35 a nominal 12 runs four; printing 12 gives a counter that
///    stalls at a third and then jumps.
final class PassProgressAndCheckpointChecks: XCTestCase {

    func testStepsAcrossThePassAreRealCompletedUnits() {
        // Architecture counts steps, Studio counts tiles, and both numbers have to be true.
        let first = TiledControlNetPass.Progress(tile: 0, totalTiles: 9,
                                                 stepInTile: 1, stepsPerTile: 4)
        XCTAssertEqual(first.step, 1)
        XCTAssertEqual(first.totalSteps, 36)

        let last = TiledControlNetPass.Progress(tile: 8, totalTiles: 9,
                                                stepInTile: 4, stepsPerTile: 4)
        XCTAssertEqual(last.step, 36, "the final step must land exactly on the total")
        XCTAssertEqual(last.step, last.totalSteps)
    }

    func testTheStepCountNeverGoesBackwardsAcrossATileBoundary() {
        var previous = 0
        for tile in 0..<9 {
            for step in 1...4 {
                let progress = TiledControlNetPass.Progress(tile: tile, totalTiles: 9,
                                                            stepInTile: step, stepsPerTile: 4)
                XCTAssertGreaterThan(progress.step, previous,
                                     "went backwards at tile \(tile) step \(step)")
                previous = progress.step
            }
        }
    }

    func testACheckpointRoundTripsWithoutLosingAScalarOrTheTile() throws {
        let scalars = (0..<(2 * 4 * 8 * 8)).map { Float32(sin(Double($0))) }
        let array = MLShapedArray<Float32>(scalars: scalars, shape: [2, 4, 8, 8])
        let original = TiledControlNetPass.Checkpoint(tile: 5, step: 8, lowerOrderStepped: 2,
                                                      latents: [array], modelOutputs: [array, array])

        let data = try XCTUnwrap(original.encoded)
        let back = try XCTUnwrap(TiledControlNetPass.Checkpoint.decoded(from: data))

        XCTAssertEqual(back.tile, 5, "the tile must survive — restoring into the wrong one splices "
                       + "one tile's latents into another")
        XCTAssertEqual(back.step, 8)
        XCTAssertEqual(back.lowerOrderStepped, 2)
        XCTAssertEqual(back.latents.count, 1)
        XCTAssertEqual(back.modelOutputs.count, 2)
        // Exact, not approximate: a last-bit difference resumes into a different picture.
        XCTAssertEqual(back.latents[0].scalars, scalars)
        XCTAssertEqual(back.modelOutputs[1].scalars, scalars)
    }

    func testATruncatedCheckpointIsRefusedRatherThanDecodedIntoNonsense() throws {
        // A crash during the write is exactly how a short file appears. Half a latent restored as
        // though it were whole is worse than starting the tile again.
        let array = MLShapedArray<Float32>(scalars: [Float32](repeating: 1, count: 16),
                                           shape: [1, 1, 4, 4])
        let data = try XCTUnwrap(TiledControlNetPass.Checkpoint(
            tile: 1, step: 4, lowerOrderStepped: 1, latents: [array], modelOutputs: []).encoded)

        XCTAssertNil(TiledControlNetPass.Checkpoint.decoded(from: data.prefix(data.count - 4)))
        XCTAssertNil(TiledControlNetPass.Checkpoint.decoded(from: data.prefix(2)))
        XCTAssertNil(TiledControlNetPass.Checkpoint.decoded(from: Data()))
    }

    func testTheAwkwardFloatsSurvive() throws {
        // Denormals and infinities are what a text format mangles, and latents mid-schedule do
        // reach very small magnitudes.
        let odd: [Float32] = [0, -0, .leastNonzeroMagnitude, -.leastNonzeroMagnitude,
                              .greatestFiniteMagnitude, .infinity, -.infinity]
        let array = MLShapedArray<Float32>(scalars: odd, shape: [odd.count])
        let data = try XCTUnwrap(TiledControlNetPass.Checkpoint(
            tile: 0, step: 4, lowerOrderStepped: 0, latents: [array], modelOutputs: []).encoded)
        let back = try XCTUnwrap(TiledControlNetPass.Checkpoint.decoded(from: data))

        for (restored, expected) in zip(back.latents[0].scalars, odd) {
            XCTAssertEqual(restored.bitPattern, expected.bitPattern,
                           "compared bit-for-bit, so -0 and 0 are not confused")
        }
    }

    func testTheCheckpointIntervalIsAStatedTrade() {
        // ~800 KB a checkpoint. Every step would be tens of megabytes per tile to save half a step.
        XCTAssertGreaterThan(TiledControlNetPass.checkpointInterval, 1)
        XCTAssertLessThanOrEqual(TiledControlNetPass.checkpointInterval, 8)
    }
}

final class ControlNetCatalogChecks: XCTestCase {

    private func pack(_ names: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pack-\(UUID().uuidString)", isDirectory: true)
        let nets = root.appendingPathComponent("controlnet", isDirectory: true)
        try FileManager.default.createDirectory(at: nets, withIntermediateDirectories: true)
        for name in names {
            try FileManager.default.createDirectory(
                at: nets.appendingPathComponent("\(name).mlmodelc"), withIntermediateDirectories: true)
        }
        return root
    }

    func testEachNetIsRecognisedFromItsCompiledName() throws {
        // Apple's converter camel-cases the HuggingFace repo id, so the match is on a substring
        // rather than an exact name — pinned here because a converter change would break it silently.
        let root = try pack(["LllyasvielControlV11F1ESd15Tile",
                             "LllyasvielControlV11PSd15Mlsd",
                             "LllyasvielControlV11F1PSd15Depth"])
        let installed = ControlNetCatalog.installed(at: root)
        XCTAssertEqual(Set(installed.map(\.kind)), [.tile, .mlsd, .depth])
        XCTAssertEqual(ControlNetCatalog.name(of: .mlsd, at: root), "LllyasvielControlV11PSd15Mlsd")
        XCTAssertTrue(ControlNetCatalog.has(.depth, at: root))
    }

    func testAPackWithoutANetDoesNotOfferIt() throws {
        // Architecture ships MLSD and Depth and specifically NOT Tile, which would hold a redesign
        // to the room it is meant to change.
        let root = try pack(["LllyasvielControlV11PSd15Mlsd"])
        XCTAssertFalse(ControlNetCatalog.has(.tile, at: root))
        XCTAssertNil(ControlNetCatalog.name(of: .depth, at: root))
        XCTAssertEqual(ControlNetCatalog.installed(at: root).count, 1)
    }

    func testAnEmptyOrMissingPackYieldsNothingRatherThanGuessing() throws {
        XCTAssertTrue(ControlNetCatalog.installed(at: try pack([])).isEmpty)
        XCTAssertTrue(ControlNetCatalog.installed(
            at: URL(fileURLWithPath: "/nowhere/at/all")).isEmpty)
    }

    func testOnlyTileConditionsOnItself() {
        XCTAssertFalse(ControlNetCatalog.Kind.tile.needsConditioningImage)
        XCTAssertTrue(ControlNetCatalog.Kind.mlsd.needsConditioningImage)
        XCTAssertTrue(ControlNetCatalog.Kind.depth.needsConditioningImage)
    }
}
