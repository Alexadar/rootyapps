import XCTest
import CoreML
import CoreGraphics
@preconcurrency import DiffusionKit
import TaskKit
@testable import Wallpapers

/// **The gate for stage 1 resumption.**
///
/// A wrong restore does not crash and does not throw. It resumes into slightly different solver
/// state and produces a *slightly different picture from the same seed* — which is invisible to
/// every other test in this suite, and which a user would read as the model being unreliable rather
/// than as a bug. Nothing short of comparing pixels catches it.
///
/// So: the same prompt and seed, run twice.
///
/// 1. Straight through, `n` steps → image A.
/// 2. Stopped after `n/2` steps, then resumed from the checkpoint → image B.
///
/// **A and B must be byte-identical.** Anything else means the scheduler state is wrong, and stage 1
/// resumption does not ship.
///
/// ### Why it is opt-in
///
/// It loads the real 1.1 GB model and runs a real de-noising loop one and a half times — around a
/// minute on this Mac. That does not belong in a suite that runs in three seconds on every build.
/// Run it deliberately:
///
/// ```
/// TEST_RUNNER_WP_SPLIT_RUN=1 xcodebuild test -project wallpapers.xcodeproj -scheme wallpapers \
///     -destination 'platform=macOS' \
///     -only-testing:wallpapersUnitTests/SplitRunEqualityCheck
/// ```
///
/// The `TEST_RUNNER_` prefix is required — `xcodebuild` does not pass the shell's environment to the
/// test process, and without it both tests skip and the run still reports success.
///
/// Last run: **passed**, 0 of 786,432 bytes differing, ~283 s for five real de-noising runs.
final class SplitRunEqualityCheck: XCTestCase {

    private static let steps = 12
    private static let interruptAfter = 6
    private static let prompt = "a slate coastline under fog, wide horizon"
    private static let seed: UInt32 = 4242

    func testAResumedRunProducesTheSamePixelsAsAnUninterruptedOne() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["WP_SPLIT_RUN"] == "1",
                          "Opt-in: loads the real model and runs the loop one and a half times.")
        let resources = try XCTUnwrap(CoreMLImageGenerator.bundledResourcesURL(),
                                      "No model in the bundle — nothing to check.")

        let straight = try run(resources: resources, resumingFrom: nil, stoppingAfter: nil)
        let (_, checkpoint) = try runCapturing(resources: resources, stoppingAfter: Self.interruptAfter)
        let resumed = try run(resources: resources,
                              resumingFrom: try XCTUnwrap(checkpoint, "no checkpoint was written"),
                              stoppingAfter: nil)

        let a = try XCTUnwrap(Bitmap.pngData(cg: straight))
        let b = try XCTUnwrap(Bitmap.pngData(cg: resumed))

        // Compared as pixels rather than as files: PNG encoding is deterministic here, but a
        // difference in the *encoder* would be a confusing way to fail a test about latents.
        XCTAssertEqual(straight.width, resumed.width)
        XCTAssertEqual(straight.height, resumed.height)
        let (left, right) = (try pixels(of: straight), try pixels(of: resumed))
        let differing = zip(left, right).filter { $0 != $1 }.count
        XCTAssertEqual(differing, 0,
                       "\(differing) of \(left.count) bytes differ — the resumed run took a "
                       + "different path through the schedule")
        XCTAssertEqual(a, b, "same pixels, and the same file")
    }

    /// Round-trips the checkpoint through the codec on the way, because that is what the app does —
    /// a resumed run reads its state from disk, not from memory.
    func testTheCheckpointSurvivesDiskOnItsWayToTheResume() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["WP_SPLIT_RUN"] == "1",
                          "Opt-in: loads the real model.")
        let resources = try XCTUnwrap(CoreMLImageGenerator.bundledResourcesURL())

        let (_, captured) = try runCapturing(resources: resources, stoppingAfter: Self.interruptAfter)
        let checkpoint = try XCTUnwrap(captured)
        let encoded = try XCTUnwrap(JobStore.encode(checkpoint))
        let decoded = try XCTUnwrap(JobStore.decode(encoded))

        let straight = try run(resources: resources, resumingFrom: nil, stoppingAfter: nil)
        let resumed = try run(resources: resources, resumingFrom: decoded, stoppingAfter: nil)
        XCTAssertEqual(try pixels(of: straight), try pixels(of: resumed))
    }

    // MARK: -

    private func configuration() -> StableDiffusionPipeline.Configuration {
        var configuration = StableDiffusionPipeline.Configuration(prompt: Self.prompt)
        configuration.stepCount = Self.steps
        configuration.seed = Self.seed
        configuration.guidanceScale = 7.5
        configuration.disableSafety = true
        configuration.schedulerType = .dpmSolverMultistepScheduler
        return configuration
    }

    private func pipeline(resources: URL) throws -> StableDiffusionPipeline {
        let mlConfiguration = MLModelConfiguration()
        mlConfiguration.computeUnits = .cpuAndNeuralEngine
        let pipeline = try StableDiffusionPipeline(resourcesAt: resources,
                                                   controlNet: [],
                                                   configuration: mlConfiguration,
                                                   disableSafety: true,
                                                   reduceMemory: true)
        try pipeline.loadResources()
        return pipeline
    }

    private func run(resources: URL,
                     resumingFrom checkpoint: JobStore.Checkpoint?,
                     stoppingAfter limit: Int?) throws -> CGImage {
        let pipeline = try pipeline(resources: resources)
        defer { pipeline.unloadResources() }

        var configuration = configuration()
        if let checkpoint {
            configuration.resumePoint = ResumePoint(step: checkpoint.step,
                                                    latents: checkpoint.latents,
                                                    modelOutputs: checkpoint.modelOutputs,
                                                    lowerOrderStepped: checkpoint.lowerOrderStepped)
        }
        let images = try pipeline.generateImages(configuration: configuration) { state in
            limit.map { state.step + 1 < $0 } ?? true
        }
        return try XCTUnwrap(images.compactMap { $0 }.first, "the run produced no image")
    }

    /// Runs until `limit` steps have completed and returns the checkpoint from that moment — the
    /// state the app would have on disk when the process died.
    private func runCapturing(resources: URL,
                              stoppingAfter limit: Int) throws -> (CGImage?, JobStore.Checkpoint?) {
        let pipeline = try pipeline(resources: resources)
        defer { pipeline.unloadResources() }

        var captured: JobStore.Checkpoint?
        let images = try pipeline.generateImages(configuration: configuration()) { state in
            if let resume = state.resumeState, resume.completedSteps == limit {
                captured = JobStore.Checkpoint(step: resume.completedSteps,
                                               lowerOrderStepped: resume.lowerOrderStepped,
                                               latents: resume.latents,
                                               modelOutputs: resume.modelOutputs)
                return false        // stop, as an interruption would
            }
            return true
        }
        return (images.compactMap { $0 }.first, captured)
    }

    private func pixels(of image: CGImage) throws -> [UInt8] {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }
}
