import RedesignKit
import XCTest
@testable import Architecture

/// The engine, driven through the real model with a generator the test steps by hand.
@MainActor
final class RedesignEngineChecks: XCTestCase {

    private var root: URL!
    private var generator: SteppedRedesignGenerator!
    private var engine: RedesignEngine!

    override func setUp() async throws {
        root = Fixtures.temporaryDirectory("engine")
        generator = SteppedRedesignGenerator()
        engine = RedesignEngine(generator: generator,
                                checkpoints: CheckpointStore(root: root))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testEnqueuingStartsOnlyTheFirstVariation() async {
        engine.enqueue([Fixtures.request(variation: 1, of: 3),
                        Fixtures.request(variation: 2, of: 3),
                        Fixtures.request(variation: 3, of: 3)])
        await settle()

        XCTAssertEqual(engine.state.jobs.count, 3)
        XCTAssertEqual(engine.state.head?.request.variationIndex, 1)
        XCTAssertEqual(engine.state.queueDepth, 2)
        XCTAssertEqual(engine.state.head?.phase, .running)
    }

    func testStepsReachTheViewFacingProgress() async {
        engine.enqueue([Fixtures.request()])
        await settle()

        generator.advance(to: 18)
        await settle()

        XCTAssertEqual(engine.progress?.step, 18)
        XCTAssertEqual(engine.progress?.stage, .refining)
        XCTAssertEqual(engine.progress?.totalSteps, 32)
        XCTAssertNil(engine.progress?.pause)
        // Step-based all the way to the screen; the fraction is only ever for drawing a bar.
        XCTAssertEqual(engine.progress?.fraction ?? 0, 18.0 / 32.0, accuracy: 0.0001)
    }

    func testCancellingAtAnArbitraryStepIsDeterministic() async {
        engine.enqueue([Fixtures.request(variation: 1, of: 2),
                        Fixtures.request(variation: 2, of: 2)])
        await settle()

        generator.advance(to: 17)
        await settle()
        let head = engine.state.head!
        engine.cancel(head.id)
        await settle()

        XCTAssertEqual(engine.state.job(head.id)?.phase, .cancelled)
        // The queue survives: the handoff promises "Cancels only this variation."
        XCTAssertEqual(engine.state.head?.request.variationIndex, 2)
    }

    func testACheckpointIsWrittenOnTheCadenceAndReadBack() async {
        engine.enqueue([Fixtures.request()])
        await settle()

        generator.advance(to: 8)
        await settle()

        XCTAssertEqual(engine.state.head?.checkpointStep, 8)
        let store = CheckpointStore(root: root)
        let stored = store.read(for: engine.state.head!.id)
        XCTAssertEqual(stored?.step, 8)
        XCTAssertEqual(stored?.kind, "stepped.v1")
    }

    func testBackgroundingPausesAndForegroundResumesAtTheCheckpoint() async {
        engine.enqueue([Fixtures.request()])
        await settle()
        generator.advance(to: 12)
        await settle()

        engine.sceneChanged(.suspended)
        await settle()

        XCTAssertEqual(engine.state.head?.phase, .paused(.backgroundSuspended))
        XCTAssertEqual(engine.progress?.pause, .backgroundSuspended)

        engine.sceneChanged(.active)
        await settle()

        // Resumes from where it stopped, and the counter does not walk backwards.
        XCTAssertGreaterThanOrEqual(engine.state.head?.step ?? 0, 12)
        XCTAssertNotEqual(engine.state.head?.phase, .paused(.backgroundSuspended))
    }

    func testNothingStartsWhileTheAppIsOffScreen() async {
        engine.sceneChanged(.suspended)
        engine.enqueue([Fixtures.request()])
        await settle()

        // This build claims no background execution mode, so starting here would be a promise the
        // platform will not keep.
        XCTAssertEqual(engine.state.head?.phase, .paused(.backgroundSuspended))
        XCTAssertFalse(engine.state.head?.generatorRunning ?? true)
    }

    func testAFailureDoesNotStopTheQueue() async {
        engine.enqueue([Fixtures.request(variation: 1, of: 2),
                        Fixtures.request(variation: 2, of: 2)])
        await settle()

        generator.advance(to: 10)
        await settle()
        generator.failure = .outOfMemory
        generator.advance()
        // The throw travels continuation → Task → main actor, so wait on the post-condition
        // rather than on a fixed number of yields.
        await settle(until: { engine.state.jobs[0].phase.isTerminal },
                     "the failure never reached the queue")

        XCTAssertEqual(engine.state.jobs[0].phase,
                       .failed(reason: RedesignError.outOfMemory.plainReason))
        XCTAssertEqual(engine.state.head?.request.variationIndex, 2)
    }

    func testARejectedCheckpointIsNotAFailure() async {
        // A checkpoint written by a different pipeline — the app updated between runs.
        let request = Fixtures.request()
        let stale = GenerationCheckpoint(kind: "coreml.something.v9",
                                         requestDigest: request.digest,
                                         step: 12,
                                         totalSteps: 32,
                                         deviceID: "mock-device",
                                         state: Data([1]),
                                         createdAt: Date())
        let job = Job(id: JobID(request.id), request: request,
                      step: 12, checkpointStep: 12, enqueuedAt: Date())
        let store = CheckpointStore(root: root)
        try? store.write(stale, for: job.id)
        store.saveQueue([job])

        engine.restore()
        await settle()
        engine.resumeRestored()
        await settle(until: { engine.state.head?.checkpointRejected == true },
                     "the stale checkpoint was never rejected")

        if case .failed = engine.state.head?.phase {
            XCTFail("a rejected checkpoint must never be a failure card")
        }
        XCTAssertTrue(engine.state.head?.checkpointRejected ?? false)
        XCTAssertNil(engine.state.head?.checkpointStep)
    }

    func testRestoringAfterAKillNeverAutoStarts() async {
        var job = Job(id: JobID("living-room-1"), request: Fixtures.request(), enqueuedAt: Date())
        job.phase = .running
        job.generatorRunning = true
        job.step = 19
        job.checkpointStep = 16
        CheckpointStore(root: root).saveQueue([job])

        engine.restore()
        await settle()

        // Burning minutes of Neural Engine time because somebody opened the app to look at their
        // library is wrong.
        XCTAssertTrue(engine.state.restoredFromDisk)
        XCTAssertFalse(engine.state.head?.generatorRunning ?? true)
        // And the step is clamped back to what actually survived.
        XCTAssertEqual(engine.state.head?.step, 16)
    }

    func testThermalPressureDegradesRatherThanStopping() async {
        engine.enqueue([Fixtures.request()])
        await settle()
        generator.advance(to: 10)
        await settle()

        engine.apply(.thermalChanged(.elevated))
        await settle()

        // "Running slower to keep the phone cool … still progressing" has to be true while it is
        // on screen.
        XCTAssertEqual(engine.state.head?.phase, .running)
        XCTAssertEqual(engine.progress?.pause, .thermal)

        generator.advance()
        await settle()
        XCTAssertEqual(engine.progress?.step, 11)
    }

    func testCompletingWritesThroughToTheCoordinatorExactlyOnce() async {
        var finished: [String] = []
        engine.onVariationFinished = { job, _ in
            finished.append(job.id.rawValue)
        }
        engine.enqueue([Fixtures.request()])
        await settle()
        generator.advance(to: 32)
        await settle(until: { !finished.isEmpty }, "the completion never reached the coordinator")

        XCTAssertEqual(finished, ["living-room-1"])
        if case .complete = engine.state.head?.phase {
            XCTFail("a completed job is no longer the head")
        }
    }

    func testCancellingNeverReportsCompletion() async {
        var finished: [String] = []
        engine.onVariationFinished = { job, _ in finished.append(job.id.rawValue) }
        engine.enqueue([Fixtures.request()])
        await settle()
        generator.advance(to: 9)
        await settle()
        engine.cancel(engine.state.head!.id)
        await settle()

        XCTAssertTrue(finished.isEmpty)
    }

    func testTheEstimateStaysSilentUntilItHasMeasuredSomething() async {
        engine.enqueue([Fixtures.request()])
        await settle()
        generator.advance()
        await settle()

        // One sample is not a measurement, and a number here would be a guess wearing a
        // measurement's clothes.
        XCTAssertNil(engine.progress?.estimatedRemaining)
    }
}
