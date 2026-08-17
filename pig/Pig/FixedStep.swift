import Foundation

/// How many simulation steps to run for a given amount of real time.
///
/// Pulled out of the view's draw callback and into a value with no dependencies, because the property
/// it has to hold is worth stating and worth proving:
///
///   **The simulation never runs faster than the wall clock.**
///
/// Everything the player feels — how fast the pig walks, how long a carrot takes to grow, how long
/// the cooldown is — is stated in seconds in `WorldConfig`, and all of it is a lie if this type hands
/// out more steps than time has passed. It is also invisible: a simulation running at three times
/// speed looks like tuning, not like a bug, which is exactly how it survives a play-test.
///
/// Two deliberate compromises, both bounded:
///
///  * a frame longer than `maxFrame` is treated as `maxFrame`, so a stall or a debugger breakpoint
///    becomes a hitch rather than a teleport;
///  * at most `maxCatchUp` steps run per frame, and the leftover is discarded rather than banked —
///    banking it would let a slow machine spiral, each frame owing more than the last.
struct FixedStep {

    let dt: Double
    let maxCatchUp: Int
    let maxFrame: Double

    private var accumulator: Double = 0
    private var last: Double?

    /// Total steps handed out. Only for tests and diagnostics; nothing in the game reads it.
    private(set) var totalSteps: Int = 0

    init(dt: Double, maxCatchUp: Int = 8, maxFrame: Double = 0.25) {
        self.dt = dt
        self.maxCatchUp = maxCatchUp
        self.maxFrame = maxFrame
    }

    /// How many steps to advance, given the current value of a monotonic clock.
    mutating func steps(now: Double) -> Int {
        let elapsed = min(maxFrame, now - (last ?? now))
        last = now
        accumulator += elapsed

        var steps = 0
        while accumulator >= dt && steps < maxCatchUp {
            accumulator -= dt
            steps += 1
        }
        // At the cap the machine is behind and cannot catch up this frame. Dropping the remainder
        // makes the simulation slower than real time, which is survivable; keeping it makes the next
        // frame owe even more, which is not.
        if steps == maxCatchUp { accumulator = 0 }

        totalSteps += steps
        return steps
    }
}
