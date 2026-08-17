import XCTest
@testable import Pig

/// The wall-clock contract.
///
/// Written because a simulation running fast is invisible: it looks like tuning, not like a bug. The
/// growth timer, the drop cooldown and the dog's patience are all stated in seconds, and every one of
/// them is a lie if this type hands out more steps than time has passed.
final class FixedStepTests: XCTestCase {

    private let dt = 1.0 / 120.0

    /// A display running at exactly the simulation rate advances exactly one step per frame.
    func testOneFramePerStepAtTheMatchingRate() {
        var clock = FixedStep(dt: dt)
        var now = 1000.0
        XCTAssertEqual(clock.steps(now: now), 0, "the first frame has no elapsed time to spend")
        for _ in 0..<600 {
            now += dt
            // Not exactly 1 every time, and it must not be: adding `dt` repeatedly to a Double leaves
            // the accumulator a few ulp short every so often, so one frame in several hundred spends
            // nothing and the next spends two. Demanding exactly 1 here would be demanding that
            // floating point be exact, and the property that actually matters is the total.
            XCTAssertLessThanOrEqual(clock.steps(now: now), 1)
        }
        XCTAssertEqual(Double(clock.totalSteps), 600, accuracy: 2)
    }

    /// A 60 Hz display advances two steps a frame, and covers exactly the same ground in the same
    /// wall time as a 120 Hz one. This is the property that makes the game feel identical on a phone
    /// and on a Mac.
    func testRefreshRateChangesTheStepsPerFrameButNotThePace() {
        func stepsOverFiveSeconds(refresh: Double) -> Int {
            var clock = FixedStep(dt: dt)
            var now = 500.0
            _ = clock.steps(now: now)
            for _ in 0..<Int(refresh * 5) {
                now += 1 / refresh
                _ = clock.steps(now: now)
            }
            return clock.totalSteps
        }
        let sixty = stepsOverFiveSeconds(refresh: 60)
        let oneTwenty = stepsOverFiveSeconds(refresh: 120)
        XCTAssertEqual(sixty, oneTwenty, accuracy: 1, "60 Hz and 120 Hz drifted apart")
        XCTAssertEqual(Double(sixty) * dt, 5.0, accuracy: 0.02, "five seconds did not simulate five")
    }

    /// **The simulation never outruns the wall clock**, whatever the frame timing does.
    ///
    /// Jitter, stalls and bursts of very short frames all go in; what comes out must never add up to
    /// more seconds than actually elapsed.
    func testTheSimulationNeverRunsFasterThanRealTime() {
        var clock = FixedStep(dt: dt)
        var now = 0.0
        _ = clock.steps(now: now)

        // A deterministic mix of nasty frame times: fast, slow, a stall, a burst.
        let pattern = [1.0 / 240, 1.0 / 120, 1.0 / 60, 0.4, 1.0 / 500, 1.0 / 30, 0.002]
        for i in 0..<4000 {
            now += pattern[i % pattern.count]
            _ = clock.steps(now: now)
            XCTAssertLessThanOrEqual(Double(clock.totalSteps) * dt, now + dt,
                                     "the simulation is ahead of the wall clock after \(i) frames")
        }
    }

    /// A stall is a hitch, not a teleport: one enormous frame cannot dump a minute of simulation into
    /// the game at once.
    func testAStallIsClampedRatherThanReplayed() {
        var clock = FixedStep(dt: dt, maxCatchUp: 8, maxFrame: 0.25)
        var now = 10.0
        _ = clock.steps(now: now)
        now += 60                                    // the machine went to sleep
        XCTAssertEqual(clock.steps(now: now), 8, "a stall was replayed instead of clamped")
        now += dt
        XCTAssertEqual(clock.steps(now: now), 1, "the leftover was banked and spilled into the next frame")
    }

    /// Time is only ever spent once: a frame with no elapsed time produces no steps, however often it
    /// is called. A `draw` callback firing twice for one frame would otherwise double the pace, which
    /// is the exact shape of the bug this file was written to rule out.
    func testRepeatedCallsAtTheSameInstantProduceNothing() {
        var clock = FixedStep(dt: dt)
        var now = 3.0
        _ = clock.steps(now: now)
        now += dt * 6                              // inside the catch-up cap, so nothing is dropped
        // Five or six, depending on where `now + 6·dt` lands in floating point. The count is not the
        // property under test; what follows it is.
        XCTAssertGreaterThanOrEqual(clock.steps(now: now), 5)
        for _ in 0..<50 {
            XCTAssertEqual(clock.steps(now: now), 0, "time was spent twice")
        }
    }
}
