import XCTest
import CoreML
import CoreGraphics
@preconcurrency import DiffusionKit
import GenerationKit
import TaskKit
@testable import Wallpapers

/// **Resumption against the real models, at every stage.**
///
/// The unit suite proves the *rules* — which tiles are outstanding, whether a manifest still applies,
/// whether a checkpoint survives a round trip. None of it proves the thing that actually matters:
/// that a job which was interrupted and resumed produces **the same picture** as one that was not.
/// That failure is silent. It does not crash, it does not throw, and it looks like the model being
/// unreliable rather than like a bug.
///
/// So each stage is run twice — straight through, and interrupted then resumed — and the pixels are
/// compared. `SplitRunEqualityCheck` does this for stage 1 (the de-noising loop, where the state is
/// latents and solver history). This file does it for the two tiled stages, where the state is files
/// on disk.
///
/// ### Opt-in, macOS, on demand
///
/// It loads the 1.1 GB diffusion model and the ESRGAN model and runs several real passes — minutes,
/// not seconds. Run it deliberately:
///
/// ```
/// TEST_RUNNER_WP_SPLIT_RUN=1 xcodebuild test -project wallpapers.xcodeproj -scheme wallpapers \
///     -destination 'platform=macOS' \
///     -only-testing:wallpapersUnitTests/ResumabilityE2ECheck
/// ```
///
/// The `TEST_RUNNER_` prefix is required — `xcodebuild` does not forward the shell's environment to
/// the test process, and without it every test here skips while the run still reports success.
final class ResumabilityE2ECheck: XCTestCase {

    private var sandbox: URL!
    private var realRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["WP_SPLIT_RUN"] == "1",
                          "Opt-in: loads the real models and runs several real passes.")
        realRoot = JobStore.jobsRoot
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("resumability-e2e-\(UUID().uuidString)", isDirectory: true)
        JobStore.jobsRoot = sandbox
    }

    override func tearDown() {
        if let realRoot { JobStore.jobsRoot = realRoot }
        if let sandbox { try? FileManager.default.removeItem(at: sandbox) }
        super.tearDown()
    }

    // MARK: Stage 2 — ESRGAN tiling

    func testAnEnlargementResumedFromDiskMatchesAnUninterruptedOne() throws {
        let upscaler = try Upscaler(modelURL: try XCTUnwrap(Upscaler.bundledModelURL(),
                                                            "No upscaler in the bundle."))
        let source = Self.testPattern(side: 512)

        let straight = try upscaler.upscale(source)

        // The interruption, reproduced exactly as the disk would hold it: the tiles that finished
        // are there, the rest are not.
        let store = try JobStore.open(manifest(stage: .upscaling(tile: 0, of: 9)))
        let tiles = store.tiles(.upscale)
        _ = try upscaler.upscale(source, tiles: tiles)
        let total = Upscaler.grid(width: 512, height: 512).count
        try Self.keepOnly(firstTiles: total / 2, in: tiles, of: total)
        XCTAssertEqual(tiles.completed().count, total / 2, "the interruption was not set up")

        let resumed = try upscaler.upscale(source, tiles: tiles)

        // Every restored tile came back through a PNG. If that round trip changed a single channel
        // — a colour-space assumption, a premultiplied alpha, a BGRA/RGBA swap — the seam would show
        // up here and nowhere else.
        assertSamePixels(straight, resumed, "the resumed enlargement differs from the whole one")
    }

    func testEveryUpscaleTileIsWrittenAndReadBackByTheRightIndex() throws {
        let upscaler = try Upscaler(modelURL: try XCTUnwrap(Upscaler.bundledModelURL()))
        let store = try JobStore.open(manifest(stage: .upscaling(tile: 0, of: 9)))
        let tiles = store.tiles(.upscale)

        _ = try upscaler.upscale(Self.testPattern(side: 512), tiles: tiles)

        let expected = Upscaler.grid(width: 512, height: 512).count
        XCTAssertEqual(tiles.completed(), Set(0..<expected),
                       "a gap here is a patch of picture that a resumed run would never fill")
        for index in 0..<expected {
            let tile = try XCTUnwrap(tiles.load(index), "tile \(index) is missing")
            XCTAssertEqual(tile.width, Upscaler.tile * Upscaler.scale)
        }
    }

    // MARK: Stage 3 — ControlNet tile refine

    func testARefinementResumedAfterAnInterruptionMatchesAnUninterruptedOne() throws {
        let resources = try XCTUnwrap(CoreMLImageGenerator.bundledResourcesURL(),
                                      "No diffusion model in the bundle.")
        try XCTSkipUnless(TileRefiner.isAvailable(at: resources), "No ControlNet installed.")

        // 768², which is four tiles — enough for an interruption to be meaningful, few enough that
        // the test is a minute rather than four.
        let side = 768
        let source = Self.testPattern(side: side)
        let total = TileRefiner.grid(width: side, height: side).count
        XCTAssertEqual(total, 4, "the grid changed; pick a size that still exercises a partial run")

        let refiner = TileRefiner(resourcesURL: resources, steps: 6, strength: 0.35)
        let straight = try refiner.refine(source, prompt: Self.prompt, seed: Self.seed,
                                          progress: { _, _ in }, isCancelled: { false })

        // A real interruption, not a simulated one: the refiner checks between tiles, which is
        // exactly where a backgrounded app stops.
        let store = try JobStore.open(manifest(stage: .refining(tile: 0, of: total)))
        let tiles = store.tiles(.refine)
        let stopAfter = 2
        var completed = 0
        XCTAssertThrowsError(try refiner.refine(source, prompt: Self.prompt, seed: Self.seed,
                                                tiles: tiles,
                                                progress: { done, _ in completed = done },
                                                isCancelled: { completed >= stopAfter })) { error in
            XCTAssertEqual(error as? GenerationError, .cancelled)
        }
        XCTAssertEqual(tiles.completed().count, stopAfter,
                       "the interrupted run should have left exactly its finished tiles")

        let resumed = try refiner.refine(source, prompt: Self.prompt, seed: Self.seed,
                                         tiles: tiles,
                                         progress: { _, _ in }, isCancelled: { false })

        assertSamePixels(straight, resumed, "the resumed refinement differs from the whole one")
    }

    func testAResumedRefinementOnlyRedoesTheTilesItHasTo() throws {
        let resources = try XCTUnwrap(CoreMLImageGenerator.bundledResourcesURL())
        try XCTSkipUnless(TileRefiner.isAvailable(at: resources), "No ControlNet installed.")

        let side = 768
        let source = Self.testPattern(side: side)
        let total = TileRefiner.grid(width: side, height: side).count
        let refiner = TileRefiner(resourcesURL: resources, steps: 6, strength: 0.35)

        let store = try JobStore.open(manifest(stage: .refining(tile: 0, of: total)))
        let tiles = store.tiles(.refine)
        _ = try refiner.refine(source, prompt: Self.prompt, seed: Self.seed, tiles: tiles,
                               progress: { _, _ in }, isCancelled: { false })
        XCTAssertEqual(tiles.completed(), Set(0..<total))

        // Everything already on disk: the second pass must load the pipeline zero times and produce
        // the picture from files alone. Measured, not asserted by inspection — a refinement that
        // silently re-ran every tile would still pass a pixel comparison.
        let started = Date()
        _ = try refiner.refine(source, prompt: Self.prompt, seed: Self.seed, tiles: tiles,
                               progress: { _, _ in }, isCancelled: { false })
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertLessThan(elapsed, 5,
                          "a fully-stored refinement took \(Int(elapsed)) s — it re-ran the model "
                          + "instead of reading its own tiles")
    }

    // MARK: A whole job

    func testAGeneratorCheckpointsAndResumesThroughItsOwnJobStore() throws {
        let resources = try XCTUnwrap(CoreMLImageGenerator.bundledResourcesURL())
        let steps = 12

        // Straight through, no job behind it.
        let plain = CoreMLImageGenerator(resourcesURL: resources)
        let request = GenerationRequest(prompt: Self.prompt, negativePrompt: "",
                                        aspect: .phone, seed: Self.seed, steps: steps,
                                        guidanceScale: 7.5, upscale: false)
        let straight = try runSynchronously { try await plain.generate(request) { _ in } }
        plain.unload()

        // Interrupted: cancelled once past the halfway checkpoint, leaving one on disk.
        let store = try JobStore.open(manifest(stage: .diffusing(step: 0, of: steps)))
        let interrupted = CoreMLImageGenerator(resourcesURL: resources)
        interrupted.useCheckpointing(.init(resumeFrom: nil,
                                           upscaleTiles: nil,
                                           write: { store.writeCheckpoint($0) }))
        let stopAt = CoreMLImageGenerator.checkpointInterval * 2
        var seen = 0
        _ = try? runSynchronously {
            try await interrupted.generate(request) { progress in
                seen = progress.step
                if seen >= stopAt { interrupted.cancel() }
            }
        }
        interrupted.unload()
        let checkpoint = try XCTUnwrap(store.readCheckpoint(), "no checkpoint reached the disk")
        XCTAssertEqual(checkpoint.step % CoreMLImageGenerator.checkpointInterval, 0)
        XCTAssertGreaterThan(checkpoint.step, 0)
        XCTAssertLessThan(checkpoint.step, steps)

        // Resumed from what is actually on disk.
        let resuming = CoreMLImageGenerator(resourcesURL: resources)
        resuming.useCheckpointing(.init(resumeFrom: store.readCheckpoint(),
                                        upscaleTiles: nil,
                                        write: { store.writeCheckpoint($0) }))
        let resumed = try runSynchronously { try await resuming.generate(request) { _ in } }
        resuming.unload()

        XCTAssertEqual(straight.size, resumed.size)
        let differing = zip(straight.pixels, resumed.pixels).filter { $0 != $1 }.count
        XCTAssertEqual(differing, 0,
                       "\(differing) of \(straight.pixels.count) bytes differ — the job resumed onto "
                       + "a different path through the schedule")
    }

    /// Measures what one Enhance actually costs, both ways round.
    ///
    /// `reduceMemory: true` makes the pipeline unload the unet and the ControlNet at the *end of
    /// every* `generateImages` call — and a refinement calls it once per tile. Nine tiles is
    /// therefore nine load/unload cycles of a 618 MB model inside ninety seconds. This measures
    /// whether that is buying anything.
    func testWhatARefinementCostsWithAndWithoutPerTileUnloading() throws {
        let resources = try XCTUnwrap(CoreMLImageGenerator.bundledResourcesURL())
        try XCTSkipUnless(TileRefiner.isAvailable(at: resources), "No ControlNet installed.")
        let source = Self.testPattern(side: 1024)
        XCTAssertEqual(TileRefiner.grid(width: 1024, height: 1024).count, 9)

        for reduce in [true, false] {
            let meter = FootprintMeter()
            meter.start()
            let started = Date()
            let refiner = TileRefiner(resourcesURL: resources, steps: 6, strength: 0.35,
                                      reduceMemory: reduce)
            _ = try refiner.refine(source, prompt: Self.prompt, seed: Self.seed,
                                   progress: { _, _ in }, isCancelled: { false })
            let elapsed = Date().timeIntervalSince(started)
            meter.stop()
            print(String(format: "reduceMemory %@ → peak %.2f GB, %.1f s",
                         reduce ? "true " : "false",
                         Double(meter.peak) / 1_073_741_824, elapsed))
        }
    }

    /// A footprint sweep, stage by stage, so the expensive one is a number rather than a suspicion.
    ///
    /// Each stage is measured on its own with a fresh meter and the resting footprint subtracted, so
    /// what is printed is what *that stage* costs on top of an idle app. The point is not any single
    /// figure — it is that nothing on the list is an order of magnitude out of line with the others,
    /// which is how the tile loop's missing autorelease pool hid for as long as it did.
    func testEachStageIsMeasuredOnItsOwn() throws {
        let resources = try XCTUnwrap(CoreMLImageGenerator.bundledResourcesURL())
        var rows: [(String, Double, TimeInterval)] = []

        func measure(_ name: String, _ body: () throws -> Void) rethrows {
            let resting = FootprintMeter.now()
            let meter = FootprintMeter()
            meter.start()
            let started = Date()
            try body()
            let elapsed = Date().timeIntervalSince(started)
            meter.stop()
            let cost = Double(max(0, Int64(meter.peak) - Int64(resting))) / 1_073_741_824
            rows.append((name, cost, elapsed))
        }

        let request = GenerationRequest(prompt: Self.prompt, negativePrompt: "", aspect: .phone,
                                        seed: Self.seed, steps: 28, guidanceScale: 7.5, upscale: false)

        var master: CGImage?
        try measure("1  diffuse 512², 28 steps") {
            let generator = CoreMLImageGenerator(resourcesURL: resources)
            let produced = try runSynchronously { try await generator.generate(request) { _ in } }
            master = Bitmap.platformImage(rgba: produced.pixels,
                                          width: produced.size.width,
                                          height: produced.size.height)?.cgImageForRefinement
            generator.unload()
        }

        if let url = Upscaler.bundledModelURL() {
            try measure("2  upscale 512² → 2048²") {
                _ = try Upscaler(modelURL: url).upscale(Self.testPattern(side: 512))
            }
        }

        if TileRefiner.isAvailable(at: resources) {
            try measure("3  refine 1024², 9 tiles") {
                let refiner = TileRefiner(resourcesURL: resources, steps: 6, strength: 0.35)
                _ = try refiner.refine(Self.testPattern(side: 1024), prompt: Self.prompt,
                                       seed: Self.seed, progress: { _, _ in }, isCancelled: { false })
            }
        }

        let big = Self.testPattern(side: 2048)
        measure("4  fit 2048² to a phone panel") {
            _ = WallpaperFitting.fit(big, to: .phone)
        }
        measure("5  encode a 2048² master as PNG") {
            _ = Bitmap.pngData(cg: big)
        }
        if let sample = master {
            measure("6  read back a finished master") {
                _ = Bitmap.pngData(cg: sample).flatMap { Bitmap.platformImage(pngData: $0) }
            }
        }

        print("\n  stage                                  peak over idle     time")
        print("  (— = never rose above the resting footprint; not separately measurable)")
        for (name, cost, elapsed) in rows {
            let padded = name.padding(toLength: 36, withPad: " ", startingAt: 0)
            // Zero means "never rose above what the process was already holding", not "free". A
            // 34 MB spike is invisible against a resting footprint that already includes mapped
            // model pages, and saying 0 MB would be a claim the measurement cannot support.
            let amount = cost * 1024 < 1 ? "     — " : String(format: "%6.0f ", cost * 1024)
            print(String(format: "  %@ %@MB  %7.1f s", padded, amount, elapsed))
        }
        print("")

        // Set to fail on the regression that caused this sweep to exist. Refinement without an
        // autorelease pool in the tile loop peaked at 1.43 GB; with one it is ~0.31 GB. Anything
        // approaching 0.7 GB means the pools or the model retention have been lost again.
        for (name, cost, _) in rows {
            XCTAssertLessThan(cost, 0.7, "\(name) is back to pre-pool memory behaviour")
        }
    }

    // MARK: Memory

    /// Reports the peak footprint of a resumed run. **Deliberately not an assertion.**
    ///
    /// The plan called for this to be the guard against two resident pipelines — the allocation that
    /// crashed Enhance and rebooted the test phone. Measured, it cannot be:
    ///
    /// | run | peak footprint |
    /// |---|---|
    /// | generate, then unload, then refine | 0.32 GB |
    /// | generate, **no unload**, then refine | 0.35 GB |
    ///
    /// Thirty megabytes apart. On macOS Core ML maps model weights from disk, so an "unloaded"
    /// pipeline's pages are file-backed and `phys_footprint` barely moves — the exact regression is
    /// invisible here. The 1.11 GB and 776 MB figures this was meant to defend were phone
    /// measurements, and jetsam is a phone failure mode.
    ///
    /// So this prints a number and asserts only that nothing has gone wildly wrong. **The real check
    /// is on the device**, and `JobRunnerChecks` is what actually holds the invariant: the runner
    /// refuses to have two jobs at once, which is what stops the second pipeline from ever loading.
    func testTheFootprintOfAResumedRunIsReportedForTheRecord() throws {
        let resources = try XCTUnwrap(CoreMLImageGenerator.bundledResourcesURL())
        let meter = FootprintMeter()
        meter.start()

        // The real phone path: a full-length generation *with* stage 2, which is what the app runs
        // and therefore the only footprint worth reporting.
        let generator = CoreMLImageGenerator(resourcesURL: resources)
        let request = GenerationRequest(prompt: Self.prompt, negativePrompt: "", aspect: .phone,
                                        seed: Self.seed, steps: 28, guidanceScale: 7.5, upscale: true)
        let store = try JobStore.open(manifest(stage: .diffusing(step: 0, of: 28)))
        generator.useCheckpointing(.init(resumeFrom: nil, upscaleTiles: nil,
                                         write: { store.writeCheckpoint($0) }))
        _ = try runSynchronously { try await generator.generate(request) { _ in } }
        let afterGenerate = meter.peak

        // What the runner does before every `.enhance`.
        generator.unload()
        if TileRefiner.isAvailable(at: resources) {
            let refiner = TileRefiner(resourcesURL: resources, steps: 4, strength: 0.35)
            _ = try refiner.refine(Self.testPattern(side: 512), prompt: Self.prompt, seed: Self.seed,
                                   progress: { _, _ in }, isCancelled: { false })
        }
        meter.stop()

        let gigabytes = Double(meter.peak) / 1_073_741_824
        print("peak footprint: \(String(format: "%.2f", gigabytes)) GB "
              + "(after generate: \(String(format: "%.2f", Double(afterGenerate) / 1_073_741_824)) GB)")
        // A sanity bound, not a guard: measured at 0.32 GB, and 2 GB would mean something has gone
        // wrong on a scale no unit test needs to be subtle about.
        XCTAssertLessThan(gigabytes, 2.0,
                          "peaked at \(String(format: "%.2f", gigabytes)) GB")
        XCTAssertGreaterThan(gigabytes, 0.05, "nothing was measured — the meter is broken")
    }

    /// Samples the process footprint, because `phys_footprint` is a *current* reading and the number
    /// that matters is the maximum. This is the figure jetsam judges an app by, not resident size.
    private final class FootprintMeter: @unchecked Sendable {
        private var running = false
        private var maximum: UInt64 = 0
        private let lock = NSLock()

        var peak: UInt64 { lock.withLock { maximum } }

        /// The footprint right now, for taking a resting baseline before a measurement.
        static func now() -> UInt64 { footprint() }

        func start() {
            lock.withLock { running = true; maximum = 0 }
            Thread.detachNewThread { [self] in
                while lock.withLock({ running }) {
                    let sample = Self.footprint()
                    lock.withLock { maximum = max(maximum, sample) }
                    // 5 ms, not 100. A PNG encode of a 2048² master allocates tens of
                    // megabytes and finishes inside a single 100 ms tick — it would report zero,
                    // which reads as "free" rather than "never sampled".
                    Thread.sleep(forTimeInterval: 0.005)
                }
            }
        }

        func stop() { lock.withLock { running = false } }

        fileprivate static func footprint() -> UInt64 {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
        }
    }

    // MARK: -

    private static let prompt = "a slate coastline under fog, wide horizon"
    private static let seed: UInt32 = 4242

    private func manifest(stage: JobManifest.Stage) -> JobManifest {
        JobManifest(id: "e2e-\(UUID().uuidString)",
                    kind: .generate,
                    prompt: Self.prompt,
                    negativePrompt: "",
                    seed: Self.seed,
                    steps: 12,
                    guidanceScale: 7.5,
                    aspect: .phone,
                    models: [ModelUse(role: .generate, id: "sd15cn", fingerprint: "e2e")],
                    stage: stage,
                    startedAt: Date(),
                    updatedAt: Date())
    }

    /// Deterministic, and structured rather than flat — a solid colour would make a tiling bug
    /// invisible, because every tile of a solid colour composes correctly whatever the indices are.
    private static func testPattern(side: Int) -> CGImage {
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let index = (y * side + x) * 4
                pixels[index] = UInt8((x * 255) / max(side - 1, 1))
                pixels[index + 1] = UInt8((y * 255) / max(side - 1, 1))
                pixels[index + 2] = UInt8(((x ^ y) & 0xFF))
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)!
    }

    /// Leaves the disk exactly as an interruption after `firstTiles` tiles would have.
    private static func keepOnly(firstTiles kept: Int, in tiles: JobStore.TileSet, of total: Int) throws {
        for index in kept..<total {
            try? FileManager.default.removeItem(
                at: tiles.directory.appendingPathComponent(TileLedger.filename(index)))
        }
    }

    private func assertSamePixels(_ left: CGImage, _ right: CGImage, _ message: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(left.width, right.width, message, file: file, line: line)
        XCTAssertEqual(left.height, right.height, message, file: file, line: line)
        guard let a = Self.bytes(of: left), let b = Self.bytes(of: right) else {
            return XCTFail("could not read the pixels back", file: file, line: line)
        }
        let differing = zip(a, b).filter { $0 != $1 }.count
        XCTAssertEqual(differing, 0,
                       "\(message): \(differing) of \(a.count) bytes differ",
                       file: file, line: line)
    }

    private static func bytes(of image: CGImage) -> [UInt8]? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    /// Bridges the generator's `async` interface into a synchronous test without an expectation per
    /// call. These runs are tens of seconds; a timeout would only add a way for the suite to lie.
    private func runSynchronously<T>(_ body: @escaping () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let box = UnsafeMutablePointer<Result<T, Error>?>.allocate(capacity: 1)
        box.initialize(to: nil)
        defer { box.deinitialize(count: 1); box.deallocate() }

        Task {
            do { box.pointee = .success(try await body()) }
            catch { box.pointee = .failure(error) }
            semaphore.signal()
        }
        semaphore.wait()
        return try XCTUnwrap(box.pointee).get()
    }
}
