import XCTest
import MLX
@testable import CityPigeon

/// The renderer draws whatever `Snapshot` says, so the snapshot is where a drawing bug becomes a
/// testable claim rather than something to hunt for in screenshots.
final class SnapshotTests: XCTestCase {

    let w = WorldConfig.shipping

    /// The predicted arc must appear while charging and must end where the physics says it will.
    ///
    /// This is the correspondence that makes the aim assist honest: the arc is computed with the
    /// same `flightTime`/`releaseVelocity` pair the payload will actually use, so the line cannot
    /// promise something the drop will not do.
    func testTheArcAppearsWhileChargingAndEndsAtTheImpactPoint() {
        var world = World(batch: 1, config: w, seed: 4)
        let hold = Intent(moveX: MLXArray.zeros([1]), moveY: MLXArray.zeros([1]),
                          hold: MLXArray([true]))
        for _ in 0..<30 { Step.advance(&world, intent: hold) }

        let s = world.snapshot()
        XCTAssertTrue(s.holding, "the pigeon is not registering the hold")
        XCTAssertGreaterThan(s.charge, 0, "charge is not accumulating")
        XCTAssertGreaterThan(s.arc.count, 8, "no predicted arc while charging")
        XCTAssertNotNil(s.landingX, "no landing point while charging")

        // The arc starts at the bird and ends on the street.
        XCTAssertEqual(s.arc.first!.x, s.pigeonX, accuracy: 1e-3)
        XCTAssertEqual(s.arc.first!.y, s.pigeonY, accuracy: 1e-3)
        XCTAssertEqual(s.arc.last!.y, 0, accuracy: 0.05, "the arc does not reach the street")
        XCTAssertEqual(s.arc.last!.x, s.landingX!, accuracy: 0.05,
                       "the drawn arc and the reported landing point disagree")

        // And the arc is monotonically forward — a parabola drawn backwards is a rendering bug.
        for i in 1..<s.arc.count {
            XCTAssertGreaterThan(s.arc[i].x, s.arc[i - 1].x - 1e-4)
        }
    }

    /// Not charging, nothing drawn. A permanently visible arc would turn a game of feel into a game
    /// of reading a line.
    func testNoArcWhenNotCharging() {
        var world = World(batch: 1, config: w, seed: 4)
        for _ in 0..<30 { Step.advance(&world, intent: .idle(batch: 1)) }
        let s = world.snapshot()
        XCTAssertFalse(s.holding)
        XCTAssertTrue(s.arc.isEmpty)
        XCTAssertNil(s.landingX)
    }

    /// More charge must move the landing point closer to the bird. This is the charge meter's whole
    /// promise, checked at the level the player actually sees it.
    func testMoreChargeBringsTheLandingPointCloser() {
        var previous = Float.greatestFiniteMagnitude
        for holdFrames in [6, 12, 24, 40, 54] {
            var world = World(batch: 1, config: w, seed: 4)
            let hold = Intent(moveX: MLXArray.zeros([1]), moveY: MLXArray.zeros([1]),
                              hold: MLXArray([true]))
            for _ in 0..<holdFrames { Step.advance(&world, intent: hold) }
            let s = world.snapshot()
            guard let land = s.landingX else { return XCTFail("no landing point") }
            let lead = land - s.pigeonX
            XCTAssertLessThan(lead, previous,
                              "holding longer did not shorten the lead — the meter is not doing "
                              + "what the ring shows")
            previous = lead
        }
    }

    /// The snapshot must report what is on screen, so the renderer never invents entities.
    func testSnapshotReportsLiveEntitiesOnly() {
        var world = World(batch: 1, config: w, seed: 9)
        for _ in 0..<600 { Step.advance(&world, intent: Policy.autopilot(world)) }
        let s = world.snapshot()
        XCTAssertGreaterThan(s.targets.liveCount, 0, "no traffic after ten seconds")
        XCTAssertLessThanOrEqual(s.targets.liveCount, w.targetSlots)
        XCTAssertLessThanOrEqual(s.payloads.liveCount, w.payloadSlots)
        for i in 0..<s.targets.slots where s.targets.alive[i] {
            XCTAssertTrue(s.targets.x[i].isFinite)
            XCTAssertLessThan(s.targets.x[i] - s.pigeonX,
                              Float(w.visibleAheadOfPigeon + Step.cullMargin) + 2,
                              "a target is being drawn beyond the camera")
        }
    }
}
