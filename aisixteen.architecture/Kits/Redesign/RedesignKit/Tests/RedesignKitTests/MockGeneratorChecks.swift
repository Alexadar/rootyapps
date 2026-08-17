import Foundation
import Synchronization
import Testing
@testable import RedesignKit

/// Collects `GenerationStep` callbacks from a background run.
private final class StepLog: Sendable {
    private let storage = Mutex<[GenerationStep]>([])
    func append(_ step: GenerationStep) { storage.withLock { $0.append(step) } }
    var steps: [GenerationStep] { storage.withLock { $0 } }
    var indices: [Int] { steps.map(\.step) }
}

@Suite("Mock generator")
struct MockGeneratorChecks {

    @Test("A full run reports every step exactly once, in order")
    func fullRunIsComplete() async throws {
        let generator = MockRedesignGenerator(speed: .instant)
        let request = Fixture.request()
        let log = StepLog()

        let output = try await generator.generate(request, resuming: nil) { log.append($0) }

        #expect(log.indices == Array(1...32))
        #expect(output.stepsRun == 32)
        #expect(output.resumedFromStep == nil)
        #expect(output.seed == request.seed)
        #expect(output.image.isWellFormed)
    }

    @Test("Previews arrive on the planned cadence and are absent otherwise")
    func previewCadenceIsHonoured() async throws {
        let generator = MockRedesignGenerator(speed: .instant)
        let request = Fixture.request()
        let log = StepLog()
        _ = try await generator.generate(request, resuming: nil) { log.append($0) }

        for step in log.steps {
            #expect((step.preview != nil) == request.plan.emitsPreview(atStep: step.step),
                    "preview mismatch at step \(step.step)")
            if let preview = step.preview { #expect(preview.isWellFormed) }
        }
        // The last frame is always a picture.
        #expect(log.steps.last?.preview != nil)
    }

    @Test("Checkpoints arrive on the cadence and never on the last step")
    func checkpointCadenceIsHonoured() async throws {
        let generator = MockRedesignGenerator(speed: .instant)
        let request = Fixture.request()
        let log = StepLog()
        _ = try await generator.generate(request, resuming: nil) { log.append($0) }

        let offered = log.steps.compactMap { $0.checkpoint }.map(\.step)
        #expect(offered == [4, 8, 12, 16, 20, 24, 28])
        #expect(!offered.contains(32))
        // The invariant that carrying the checkpoint on the step message buys us.
        for step in log.steps {
            if let checkpoint = step.checkpoint { #expect(checkpoint.step == step.step) }
        }
    }

    @Test("Resuming emits only the remaining steps and never an earlier one")
    func resumeIsContinuous() async throws {
        let generator = MockRedesignGenerator(speed: .instant)
        let request = Fixture.request()
        let checkpoint = Fixture.checkpoint(for: request, step: 12)
        let log = StepLog()

        let output = try await generator.generate(request, resuming: checkpoint) { log.append($0) }

        #expect(log.indices == Array(13...32))
        #expect(log.indices.allSatisfy { $0 > 12 })
        #expect(output.stepsRun == 20)
        #expect(output.resumedFromStep == 12)
    }

    @Test("A resumed run produces the same picture as an uninterrupted one")
    func resumeIsVisuallyContinuous() async throws {
        // The preview is a deterministic function of (seed, step), which is how a resume can be
        // checked by eye rather than only by assertion: the image does not jump.
        let request = Fixture.request()
        let whole = StepLog()
        let resumed = StepLog()

        let full = try await MockRedesignGenerator(speed: .instant)
            .generate(request, resuming: nil) { whole.append($0) }
        let partial = try await MockRedesignGenerator(speed: .instant)
            .generate(request, resuming: Fixture.checkpoint(for: request, step: 12)) { resumed.append($0) }

        #expect(full.image == partial.image)
        let wholeAt20 = whole.steps.first { $0.step == 20 }?.preview
        let resumedAt20 = resumed.steps.first { $0.step == 20 }?.preview
        #expect(wholeAt20 == resumedAt20)
    }

    @Test("A checkpoint from another generator is refused, not silently ignored")
    func foreignCheckpointIsRefused() async throws {
        let generator = MockRedesignGenerator(speed: .instant)
        let request = Fixture.request()
        let foreign = Fixture.checkpoint(for: request, step: 12, kind: "coreml.depth-sd15.v1")

        await #expect(throws: RedesignError.checkpointRejected(.kindMismatch)) {
            _ = try await generator.generate(request, resuming: foreign) { _ in }
        }
    }

    @Test("A checkpoint from another device is refused")
    func foreignDeviceIsRefused() async throws {
        let generator = MockRedesignGenerator(speed: .instant)
        let request = Fixture.request()
        let foreign = Fixture.checkpoint(for: request, step: 12, deviceID: "some-other-phone")

        await #expect(throws: RedesignError.checkpointRejected(.foreignDevice)) {
            _ = try await generator.generate(request, resuming: foreign) { _ in }
        }
    }

    @Test("captureCheckpoint returns state as of the step just finished")
    func captureIsFresherThanTheCadence() async throws {
        // On a background transition this is what saves the three steps since the last cadence
        // write. Returning a stale one would silently throw that work away.
        let generator = MockRedesignGenerator(speed: .instant)
        let request = Fixture.request()

        let seen = Mutex<Int?>(nil)
        _ = try await generator.generate(request, resuming: nil) { step in
            if step.step == 15 {
                // Not on the cadence — 15 is not a multiple of 4.
                #expect(step.checkpoint == nil)
            }
            if step.step == 15 { seen.withLock { $0 = 15 } }
        }
        #expect(seen.withLock { $0 } == 15)

        // A fresh run stopped mid-way exposes its newest state.
        let midway = MockRedesignGenerator(speed: .instant)
        let task = Task { try await midway.generate(request, resuming: nil) { step in
            if step.step == 9 { midway.cancel() }
        } }
        _ = try? await task.value
        let captured = await midway.captureCheckpoint()
        #expect(captured?.step == 9)
    }

    @Test("A finished run holds no resumable state")
    func finishedRunHasNoCheckpoint() async throws {
        let generator = MockRedesignGenerator(speed: .instant)
        _ = try await generator.generate(Fixture.request(), resuming: nil) { _ in }
        let captured = await generator.captureCheckpoint()
        #expect(captured == nil)
    }

    @Test("Cancelling stops the run between steps")
    func cancelStops() async throws {
        let generator = MockRedesignGenerator(speed: .instant)
        let log = StepLog()

        await #expect(throws: RedesignError.cancelled) {
            _ = try await generator.generate(Fixture.request(), resuming: nil) { step in
                log.append(step)
                if step.step == 17 { generator.cancel() }
            }
        }
        #expect(log.indices.last == 17)
        #expect(log.indices.count == 17)
    }
}

@Suite("Failing and non-resumable generators")
struct FailureModeChecks {

    @Test("The failure lands at the scripted step, after the frame is on screen")
    func failsWhereScripted() async throws {
        let generator = FailingRedesignGenerator(failAtStep: 11, error: .outOfMemory, speed: .instant)
        let log = StepLog()

        await #expect(throws: RedesignError.outOfMemory) {
            _ = try await generator.generate(Fixture.request(), resuming: nil) { log.append($0) }
        }
        // Ten steps reported first: by then the UI has morphed into a picture frame and a preview
        // is on screen. Failing at step 0 would never exercise unwinding from that.
        #expect(log.indices == Array(1...10))
        #expect(log.steps.contains { $0.preview != nil })
    }

    @Test("Cancelling wins over a scheduled failure")
    func cancellationBeatsTheFailure() async throws {
        // The user pressed a button. The machine's opinion about what was about to go wrong is
        // not the story to tell, and a failure card for a deliberate cancel is a bug.
        let generator = FailingRedesignGenerator(failAtStep: 11, error: .outOfMemory, speed: .instant)
        let log = StepLog()

        await #expect(throws: RedesignError.cancelled) {
            _ = try await generator.generate(Fixture.request(), resuming: nil) { step in
                log.append(step)
                if step.step == 5 { generator.cancel() }
            }
        }
        #expect(log.indices.last == 5)
    }

    @Test("Cancellation and a rejected checkpoint are not user-facing failures")
    func someErrorsAreNotFailures() {
        #expect(!RedesignError.cancelled.isUserFacingFailure)
        #expect(!RedesignError.checkpointRejected(.kindMismatch).isUserFacingFailure)
        #expect(RedesignError.outOfMemory.isUserFacingFailure)
        #expect(RedesignError.modelUnavailable.isUserFacingFailure)
        #expect(RedesignError.failed(reason: "x").isUserFacingFailure)

        // No error codes, no "an error occurred", no blame.
        for error in [RedesignError.modelUnavailable, .outOfMemory, .sourceUnreadable, .depthUnavailable] {
            let reason = error.plainReason.lowercased()
            #expect(!reason.contains("error"))
            #expect(!reason.contains("code"))
            #expect(!reason.isEmpty)
        }
    }

    @Test("A generator that cannot resume restarts cleanly instead of crashing")
    func nonResumableDegrades() async throws {
        // When the real Core ML pipeline lands, "we could not checkpoint this model" has to be a
        // supported configuration rather than a stuck job.
        let generator = RejectingCheckpointGenerator()
        let request = Fixture.request()

        #expect(await generator.captureCheckpoint() == nil)
        await #expect(throws: RedesignError.self) {
            _ = try await generator.generate(request,
                                             resuming: Fixture.checkpoint(for: request, step: 12)) { _ in }
        }

        let log = StepLog()
        let output = try await generator.generate(request, resuming: nil) { log.append($0) }
        #expect(log.indices == Array(1...32))
        #expect(output.stepsRun == 32)
    }
}

@Suite("Scripted interruptions reach the reducer")
struct InterruptibleGeneratorChecks {

    @Test("Cues publish through the same sink the real observers use")
    func cuesBecomeEvents() async throws {
        let sink = RecordingEventSink()
        let generator = InterruptibleRedesignGenerator(
            base: MockRedesignGenerator(speed: .instant),
            cues: [.init(step: 5, interruption: .thermal(.elevated)),
                   .init(step: 9, interruption: .call(active: true)),
                   .init(step: 14, interruption: .call(active: false)),
                   .init(step: 20, interruption: .scene(.suspended))],
            sink: sink)

        _ = try await generator.generate(Fixture.request(), resuming: nil) { _ in }

        #expect(sink.events == [.thermalChanged(.elevated),
                                .callChanged(active: true),
                                .callChanged(active: false),
                                .sceneChanged(.suspended)])
    }

    @Test("A scripted run drives the reducer to the right phase")
    func scriptedRunDrivesTheQueue() async throws {
        // The whole interruption path, end to end, with no device: the generator fires the same
        // events CallKit and ProcessInfo would, and the reducer reacts to them identically.
        let sink = RecordingEventSink()
        let generator = InterruptibleRedesignGenerator(
            base: MockRedesignGenerator(speed: .instant),
            cues: [.init(step: 6, interruption: .thermal(.critical))],
            sink: sink)

        _ = try await generator.generate(Fixture.request(), resuming: nil) { _ in }

        var driver = Driver.running(Fixture.variations(1), toStep: 6)
        for event in sink.events { driver.send(event) }

        #expect(driver.headPhase == .paused(.thermal))
        #expect(driver.head?.displayedPause == .thermal)
    }
}

@Suite("Mock depth estimator")
struct MockDepthEstimatorChecks {

    @Test("It writes a usable control image and never claims to be the real model")
    func writesSyntheticDepth() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("arch-depth-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("depth.raw")
        let estimator = MockDepthEstimator()
        let signal = try await estimator.estimate(Fixture.handle("source.heic"), writingTo: destination)

        #expect(signal.kind == .depth)
        #expect(signal.image.size == PixelSize(width: 512, height: 512))
        #expect(FileManager.default.fileExists(atPath: destination.path))

        // It must NOT claim `.estimated` — that would put "Depth estimated — geometry will hold"
        // on screen over a gradient.
        #expect(signal.provenance == .synthetic)
        #expect(!signal.provenance.isMeasured)

        let written = try Data(contentsOf: destination)
        #expect(written.count == 512 * 512 * 4)
        // Disparity convention: the bottom of the frame is nearest, so it is brightest.
        let topCentre = written[(10 * 512 + 256) * 4]
        let bottomCentre = written[(500 * 512 + 256) * 4]
        #expect(bottomCentre > topCentre)
    }
}
