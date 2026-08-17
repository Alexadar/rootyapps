import XCTest
@testable import TaskKit

/// The one owner of model work.
///
/// The property under test is not "it runs jobs" — it is **it refuses to run two**. Two resident
/// pipelines is roughly 1.5 GB, which is what crashed Enhance and what rebooted the test phone, and
/// nothing about that failure looks like a concurrency bug when it happens: the app simply dies. So
/// every path into model work is checked for the refusal, in both directions, rather than only the
/// one that was hit in practice.
@MainActor
final class JobRunnerChecks: XCTestCase {

    /// Runs when told to, so a job can be held open across assertions without sleeping.
    private final class Gate: @unchecked Sendable {
        private let semaphore = DispatchSemaphore(value: 0)
        func open() { semaphore.signal() }
        func wait() { semaphore.wait() }
    }

    /// Records what the runner asked of its owner, which is now the whole of their relationship.
    private final class Residency: @unchecked Sendable {
        private let lock = NSLock()
        private var _releases = 0
        private var _cancels = 0
        var releases: Int { lock.withLock { _releases } }
        var cancels: Int { lock.withLock { _cancels } }
        func release() { lock.withLock { _releases += 1 } }
        func cancel() { lock.withLock { _cancels += 1 } }
    }

    private var residency = Residency()

    private func runner() -> JobRunner {
        residency = Residency()
        return JobRunner(releaseModels: { [residency] in residency.release() },
                         cancelWork: { [residency] in residency.cancel() })
    }

    func testEnhanceReleasesWhateverWasResidentAndGenerateDoesNot() async {
        // The rule the runner exists for: a refinement loads its own pipeline including a
        // ControlNet, and the generation models must be gone before it does. Two resident pipelines
        // is what crashed Enhance and rebooted the test phone.
        let runner = runner()
        runner.start(.enhance) { _ in }
        await idle(runner)
        XCTAssertEqual(residency.releases, 1)

        runner.start(.generate) { _ in }
        await idle(runner)
        XCTAssertEqual(residency.releases, 1, "a generation must not evict what it is about to use")
    }

    func testAFreshRunnerIsIdleAndWillTakeEitherKindOfWork() {
        let runner = runner()
        XCTAssertTrue(runner.isIdle)
        XCTAssertNil(runner.current)
        XCTAssertTrue(runner.canStart(.generate))
        XCTAssertTrue(runner.canStart(.enhance))
    }

    func testWhileEnhancingNothingElseMayStart() async {
        let runner = runner()
        let gate = Gate()
        let started = expectation(description: "enhance started")

        XCTAssertTrue(runner.start(.enhance) { _ in
            started.fulfill()
            gate.wait()
        })
        await fulfillment(of: [started], timeout: 2)

        XCTAssertEqual(runner.current, .enhance)
        XCTAssertFalse(runner.isIdle)
        XCTAssertFalse(runner.canStart(.generate), "a generation during an Enhance is the crash")
        XCTAssertFalse(runner.canStart(.enhance), "including a second Enhance")

        // Refused, and — the part that matters — the refused work never ran.
        var secondRan = false
        XCTAssertFalse(runner.start(.generate) { _ in secondRan = true })
        XCTAssertFalse(secondRan)

        gate.open()
        await idle(runner)
    }

    func testWhileGeneratingAnEnhanceIsRefusedToo() async {
        let runner = runner()
        let gate = Gate()
        let started = expectation(description: "generate started")

        runner.start(.generate) { _ in
            started.fulfill()
            gate.wait()
        }
        await fulfillment(of: [started], timeout: 2)

        XCTAssertEqual(runner.current, .generate)
        XCTAssertFalse(runner.canStart(.enhance))

        gate.open()
        await idle(runner)
    }

    func testTheRunnerBecomesIdleAgainAndTakesTheNextJob() async {
        let runner = runner()
        let first = expectation(description: "first finished")
        runner.start(.generate) { _ in first.fulfill() }
        await fulfillment(of: [first], timeout: 2)
        await idle(runner)

        XCTAssertTrue(runner.isIdle)
        let second = expectation(description: "second ran")
        XCTAssertTrue(runner.start(.enhance) { _ in second.fulfill() })
        await fulfillment(of: [second], timeout: 2)
        await idle(runner)
    }

    func testAFailingJobStillReleasesTheRunner() async {
        // A job that throws its way out must not leave the app unable to start anything ever again —
        // and there is no user-visible symptom to diagnose from, only buttons that stay grey.
        let runner = runner()
        let ran = expectation(description: "ran")
        runner.start(.generate) { _ in
            defer { ran.fulfill() }
            struct Boom: Error {}
            let result: Result<Void, Error> = .failure(Boom())
            _ = try? result.get()
        }
        await fulfillment(of: [ran], timeout: 2)
        await idle(runner)
        XCTAssertTrue(runner.isIdle)
    }

    func testCancelSetsTheFlagTheWorkActuallyReads() async {
        // Core ML calls are long and synchronous: they never reach a suspension point, so
        // `Task.isCancelled` is not enough on its own. The flag is what the refiner's per-tile check
        // reads, and it must already be set by the time the job looks.
        let runner = runner()
        let gate = Gate()
        let started = expectation(description: "started")
        let observed = expectation(description: "observed the cancel")

        runner.start(.enhance) { flag in
            XCTAssertFalse(flag.isSet, "a fresh job must not begin already cancelled")
            started.fulfill()
            gate.wait()
            XCTAssertTrue(flag.isSet)
            observed.fulfill()
        }
        await fulfillment(of: [started], timeout: 2)

        runner.cancel()
        gate.open()
        await fulfillment(of: [observed], timeout: 2)
        await idle(runner)
    }

    func testEachJobGetsItsOwnFlagSoAnOldCancelCannotStopANewJob() async {
        let runner = runner()
        let firstStarted = expectation(description: "first started")
        let gate = Gate()

        runner.start(.generate) { _ in
            firstStarted.fulfill()
            gate.wait()
        }
        await fulfillment(of: [firstStarted], timeout: 2)
        runner.cancel()
        gate.open()
        await idle(runner)

        let checked = expectation(description: "second checked its flag")
        runner.start(.generate) { flag in
            XCTAssertFalse(flag.isSet, "the previous job's cancel leaked into the next one")
            checked.fulfill()
        }
        await fulfillment(of: [checked], timeout: 2)
        await idle(runner)
    }

    // MARK: -

    /// Waits for the runner to release, without sleeping on a fixed interval.
    private func idle(_ runner: JobRunner) async {
        for _ in 0..<200 where !runner.isIdle {
            await Task.yield()
        }
        XCTAssertTrue(runner.isIdle, "the runner never released")
    }
}
