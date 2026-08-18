import XCTest
@testable import Pig

/// Whether the feet are planted, asked as arithmetic instead of squinted at.
final class WalkCycleTests: XCTestCase {

    private let c = WorldConfig.shipping

    /// **A planted foot does not move.** The body advances while the foot is down, and the foot slides
    /// backward through the body's frame at exactly that rate — so its position in the world is a
    /// constant for the whole stance. Off by any amount and that is the distance every foot skates.
    func testAPlantedFootDoesNotMove() {
        for fat in stride(from: 0.0, through: 1.0, by: 0.1) {
            let cycle = WalkCycle(fat: fat, in: c)
            // Walk through one stance, sampling as the pig travels.
            let start = 0.0, end = cycle.stride * cycle.duty
            let first = cycle.worldFoot(travelled: start)
            for step in 1...60 {
                let travelled = start + (end - start) * Double(step) / 61
                XCTAssertEqual(cycle.worldFoot(travelled: travelled), first, accuracy: 1e-12,
                               "at fat \(fat) the planted foot moved \(cycle.worldFoot(travelled: travelled) - first) m")
            }
        }
    }

    /// The swing carries the foot from behind the pig to in front of it, and lifts it clear on the way.
    func testTheSwingCarriesTheFootForwardAndLiftsIt() {
        let cycle = WalkCycle(fat: 0.4, in: c)
        let back = cycle.foot(at: cycle.duty - 1e-9)
        let front = cycle.foot(at: 0.999999)
        XCTAssertLessThan(back.reach, 0, "stance should end with the foot behind the hip")
        XCTAssertGreaterThan(front.reach, 0, "swing should end with the foot in front of the hip")
        XCTAssertEqual(back.lift, 0, "a foot in stance must be on the ground")
        XCTAssertEqual(cycle.foot(at: cycle.duty + (1 - cycle.duty) / 2).lift, 1, accuracy: 1e-9,
                       "the swing should peak halfway through")
    }

    /// Duty above a half is what separates a walk from a trot, and it is what keeps two or three feet
    /// on the ground at all times.
    func testAtLeastTwoFeetAreAlwaysDown() {
        let cycle = WalkCycle(fat: 0.5, in: c)
        XCTAssertGreaterThan(cycle.duty, 0.5, "a duty at or below a half is a trot, not a walk")
        for step in 0..<200 {
            let now = Double(step) / 200
            let down = WalkCycle.phaseOffsets.filter { cycle.foot(at: now + $0).lift == 0 }.count
            XCTAssertGreaterThanOrEqual(down, 2, "only \(down) feet down at phase \(now)")
        }
    }

    /// The four feet are spread evenly around the cycle: no two leave the ground together, which is
    /// what a diagonal trot does and what made the first version bounce.
    func testTheFeetAreEvenlySpacedAroundTheCycle() {
        XCTAssertEqual(WalkCycle.phaseOffsets.count, 4)
        for (a, b) in zip(WalkCycle.phaseOffsets, WalkCycle.phaseOffsets.dropFirst()) {
            XCTAssertEqual(b - a, 0.25, accuracy: 1e-12)
        }
    }

    /// The cycle's stride is the one the engine walks on — the two numbers that must never differ.
    func testTheStrideIsTheEnginesStride() {
        for fat in stride(from: 0.0, through: 1.0, by: 0.1) {
            XCTAssertEqual(WalkCycle(fat: fat, in: c).stride,
                           2 * Double.pi / c.cadence(atFat: fat), accuracy: 1e-12)
        }
    }
}
