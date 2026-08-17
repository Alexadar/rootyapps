import XCTest
import TaskKit
@testable import Wallpapers

/// The tile grids for stages 2 and 3.
///
/// These were two nested loops until resumability needed a tile to have a *name*. The index into the
/// grid is now that name — it is what the file on disk is called and what goes into the manifest —
/// so the grid has to be exactly reproducible between a run and its resumption, and every origin has
/// to be distinct. Two indices pointing at one square means a resumed run is silently short of a
/// tile, and the missing patch is a soft rectangle nothing reports.
final class TileGridChecks: XCTestCase {

    // MARK: Stage 3 — the refiner, 512 tiles overlapping by 64

    func testTheRefinerCoversTheWorkingSizeItActuallyUses() {
        // 1024², the working size: three origins per axis, so **nine** tiles, not the four the
        // file's prose claims. The stride is `tile - overlap` = 448, which reaches 0 and 448, and
        // then the last origin is pulled back to 512 so the final tile is full rather than running
        // off the edge. That pull-back leaves 448 and 512 overlapping by 448 — the middle tile is
        // nearly redundant work.
        //
        // Asserted as it is rather than as it ought to be: redistributing the origins (0, 256, 512)
        // would cost the same nine tiles and blend better, but it moves pixels, and no measurement
        // has been taken against it.
        let grid = TileRefiner.grid(width: 1024, height: 1024)
        XCTAssertEqual(grid.count, 9)
        XCTAssertEqual(grid.map(\.x), [0, 448, 512, 0, 448, 512, 0, 448, 512])
        XCTAssertEqual(grid.map(\.y), [0, 0, 0, 448, 448, 448, 512, 512, 512])
    }

    func testTheRefinerNeverStepsOffTheEdge() {
        for side in [512, 640, 1024, 1152, 2048] {
            for origin in TileRefiner.grid(width: side, height: side) {
                XCTAssertLessThanOrEqual(origin.x + TileRefiner.tile, side)
                XCTAssertLessThanOrEqual(origin.y + TileRefiner.tile, side)
                XCTAssertGreaterThanOrEqual(origin.x, 0)
                XCTAssertGreaterThanOrEqual(origin.y, 0)
            }
        }
    }

    func testTheRefinerGridIsInWorkingOrderAndTheIndexIsStable() {
        // Left to right, top to bottom. The order is the tile's identity, so a change here silently
        // remaps every stored tile of every paused job.
        let grid = TileRefiner.grid(width: 1024, height: 1024)
        XCTAssertEqual(grid.indices.map { TileLedger.filename($0) }.prefix(4),
                       ["tile-000.png", "tile-001.png", "tile-002.png", "tile-003.png"])
        XCTAssertEqual(grid.prefix(4).map { [$0.x, $0.y] },
                       [[0, 0], [448, 0], [512, 0], [0, 448]])
        XCTAssertEqual(grid.last.map { [$0.x, $0.y] }, [512, 512])
    }

    // MARK: Stage 2 — the upscaler, 256 tiles overlapping by 16

    func testTheUpscalerCoversEverySourcePixel() {
        for side in [256, 512, 896, 1024] {
            let grid = Upscaler.grid(width: side, height: side)
            var covered = Set<Int>()
            for origin in grid {
                for x in origin.x..<(origin.x + Upscaler.tile) { covered.insert(x) }
            }
            XCTAssertEqual(covered.count, side,
                           "a column of the source was never enlarged at side \(side)")
        }
    }

    func testEveryUpscalerOriginIsDistinct() {
        // Clamping the last start back to the edge can land it on the previous origin. Two indices
        // for one square would mean a resumed run finds a "complete" ledger with a square missing.
        for side in [256, 272, 512, 528, 896, 1024, 1030] {
            let grid = Upscaler.grid(width: side, height: side)
            let unique = Set(grid.map { "\($0.x),\($0.y)" })
            XCTAssertEqual(unique.count, grid.count, "duplicate tile origin at side \(side)")
        }
    }

    func testTheUpscalerNeverStepsOffTheEdge() {
        for side in [256, 512, 896, 1024, 1030] {
            for origin in Upscaler.grid(width: side, height: side) {
                XCTAssertLessThanOrEqual(origin.x + Upscaler.tile, max(side, Upscaler.tile))
                XCTAssertLessThanOrEqual(origin.y + Upscaler.tile, max(side, Upscaler.tile))
            }
        }
    }

    func testAnImageSmallerThanOneTileIsASingleTile() {
        XCTAssertEqual(Upscaler.grid(width: 128, height: 128).count, 1)
        XCTAssertEqual(TileRefiner.grid(width: 256, height: 256).count, 1)
    }

    // MARK: The two grids must not be confused for one another

    func testTheTwoStagesNumberDifferentGrids() {
        // Same picture, different tile sizes: 512² is one refiner tile but nine upscaler tiles. This
        // is why the two stages get separate directories — a shared one would let stage 2's tile 3
        // be loaded as stage 3's.
        XCTAssertNotEqual(Upscaler.grid(width: 512, height: 512).count,
                          TileRefiner.grid(width: 512, height: 512).count)
        XCTAssertNotEqual(JobStore.TilePhase.upscale.rawValue, JobStore.TilePhase.refine.rawValue)
    }
}
