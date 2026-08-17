import XCTest
@testable import Pig

/// Properties of the animal itself, swept across the whole `fat` range.
///
/// These are the tests that only exist because the body is derived in `Engine/Shape.swift` rather
/// than modelled in a vertex shader. "The pig always gets bigger when it eats", "the belly never
/// sinks through the field", "the legs can always reach the ground" are statements about a pure
/// function of one number, and a pure function of one number can be swept.
///
/// The sweep is a **batch**: one `PigShape.derive` call over 513 fat values. That is the same call
/// the game makes at `N = 1`, which is what makes these results about the shipping code path rather
/// than about a test-only reimplementation of it.
final class ShapeOracleTests: XCTestCase {

    /// Fat values from 0 to 1 inclusive, as one `[N]` tensor.
    private static let steps = 512
    private static func sweep() -> Tensor {
        Tensor(shape: [steps + 1], data: (0...steps).map { Double($0) / Double(steps) })
    }

    private static func bodies() -> [BodyShape] {
        let b = PigShape.derive(fat: sweep())
        return (0...steps).map { i in
            BodyShape(snout: b.snout[i], head: b.head[i], chest: b.chest[i], belly: b.belly[i],
                      rump: b.rump[i], tailBase: b.tailBase[i], length: b.length[i],
                      stand: b.stand[i], sag: b.sag[i], squash: b.squash[i], superE: b.superE[i],
                      jowl: b.jowl[i], legLength: b.legLength[i], legRadius: b.legRadius[i],
                      legSplay: b.legSplay[i], earScale: b.earScale[i], headLift: b.headLift[i],
                      wobbleGain: b.wobbleGain[i], underside: b.underside[i])
        }
    }

    // MARK: - The one promise the game makes

    /// **Eating always makes the pig bigger.** Not "usually", and not "in the belly" — every radius
    /// is non-decreasing and the bulk is strictly increasing, everywhere on the interval.
    ///
    /// Asserted over the whole sweep rather than at a handful of preset fat values, because a preset
    /// table cannot protect a continuous control: it would pass with any amount of non-monotonic
    /// behaviour hiding between the presets.
    func testEveryRadiusGrowsWithFat() {
        let all = Self.bodies()
        for (i, (a, b)) in zip(all, all.dropFirst()).enumerated() {
            let at = "between fat \(Double(i) / Double(Self.steps)) and the next step"
            XCTAssertGreaterThanOrEqual(b.snout, a.snout, "snout shrank \(at)")
            XCTAssertGreaterThanOrEqual(b.head, a.head, "head shrank \(at)")
            XCTAssertGreaterThanOrEqual(b.chest, a.chest, "chest shrank \(at)")
            XCTAssertGreaterThanOrEqual(b.belly, a.belly, "belly shrank \(at)")
            XCTAssertGreaterThanOrEqual(b.rump, a.rump, "rump shrank \(at)")
            XCTAssertGreaterThanOrEqual(b.length, a.length, "the pig got shorter \(at)")
            XCTAssertGreaterThan(b.bulk, a.bulk, "bulk did not increase \(at)")
        }
    }

    /// The belly leads: it has to grow at least as fast as the chest, or the animal reads as merely
    /// scaled up rather than as fattened, which is the entire visual premise.
    func testTheBellyOutgrowsTheChest() {
        let all = Self.bodies()
        let lean = all.first!, round = all.last!
        XCTAssertGreaterThan(round.belly / lean.belly, round.chest / lean.chest,
                             "the belly must grow proportionally more than the chest")
        XCTAssertGreaterThan(round.belly / lean.belly, round.length / lean.length,
                             "the belly must grow proportionally more than the pig is long, or the "
                             + "pig is just a larger pig")
    }

    // MARK: - It must not sink into the field

    /// **Ground clearance is positive at every fat.**
    ///
    /// This is the property that makes `stand` derived rather than authored. The margin is generous
    /// on purpose: the wobble spring and the breathing both scale the radius by a few percent at
    /// runtime, and a clearance that is merely positive at rest is a belly that dips through the
    /// grass on every footfall.
    func testTheBellyNeverReachesTheGround() {
        for (i, s) in Self.bodies().enumerated() {
            let fat = Double(i) / Double(Self.steps)
            XCTAssertGreaterThan(s.bellyClearance, 0.09,
                                 "at fat \(fat) the belly clears the ground by only "
                                 + "\(s.bellyClearance) m")
        }
    }

    /// The legs have to be able to reach the ground from where they hang, and they hang from the
    /// belly's underside. The renderer stretches them to the field, so what this really proves is
    /// that the stretch is never asked for a *negative* length.
    func testTheLegsCanAlwaysReachTheGround() {
        for (i, s) in Self.bodies().enumerated() {
            let fat = Double(i) / Double(Self.steps)
            XCTAssertGreaterThan(s.bellyClearance, s.legRadius,
                                 "at fat \(fat) the leg is thicker (\(s.legRadius) m) than the gap "
                                 + "it has to span (\(s.bellyClearance) m) — the hoof would be "
                                 + "buried in the belly")
            XCTAssertGreaterThan(s.legLength, 0.1, "at fat \(fat) the legs have vanished")
        }
    }

    /// The shape must stay a shape: no negative or zero radii anywhere, or the surface turns itself
    /// inside out and the normals go with it.
    func testEveryDimensionStaysPositive() {
        for (i, s) in Self.bodies().enumerated() {
            let fat = Double(i) / Double(Self.steps)
            for (name, v) in [("snout", s.snout), ("head", s.head), ("chest", s.chest),
                              ("belly", s.belly), ("rump", s.rump), ("tailBase", s.tailBase),
                              ("length", s.length), ("stand", s.stand), ("squash", s.squash),
                              ("legRadius", s.legRadius), ("earScale", s.earScale),
                              ("underside", s.underside)] {
                XCTAssertGreaterThan(v, 0, "\(name) is \(v) at fat \(fat)")
                XCTAssertTrue(v.isFinite, "\(name) is not finite at fat \(fat)")
            }
            XCTAssertGreaterThanOrEqual(s.superE, 2, "the cross-section became concave at fat \(fat)")
        }
    }

    // MARK: - The batch is the game

    /// **A pig derived alone is bit-identical to the same pig derived in company.**
    ///
    /// This is the property the whole batch-first layout exists for. If it fails, every sweep above
    /// is measuring something the player never sees.
    func testBatchOfOneEqualsElementOfBatch() {
        let batch = PigShape.derive(fat: Self.sweep())
        for i in stride(from: 0, through: Self.steps, by: 37) {
            let fat = Double(i) / Double(Self.steps)
            let alone = PigShape.scalar(fat: fat)
            XCTAssertEqual(alone.belly, batch.belly[i], "belly differs at fat \(fat)")
            XCTAssertEqual(alone.stand, batch.stand[i], "stand differs at fat \(fat)")
            XCTAssertEqual(alone.length, batch.length[i], "length differs at fat \(fat)")
            XCTAssertEqual(alone.underside, batch.underside[i], "underside differs at fat \(fat)")
        }
    }

    /// Out-of-range fat is clamped rather than believed. The engine clamps too, but a shape that
    /// explodes on a bad input is a shape that will explode the first time something else does.
    func testFatOutsideTheUnitIntervalIsClamped() {
        XCTAssertEqual(PigShape.scalar(fat: -5).belly, PigShape.scalar(fat: 0).belly)
        XCTAssertEqual(PigShape.scalar(fat: 12).belly, PigShape.scalar(fat: 1).belly)
        XCTAssertGreaterThan(PigShape.scalar(fat: .infinity).bellyClearance, 0)
    }

    /// Girth is what the eating reach is measured against, so it has to track the actual widest
    /// half-width rather than being an independent number that agrees by coincidence.
    func testGirthIsTheWidestHalfWidth() {
        for fat in stride(from: 0.0, through: 1.0, by: 0.05) {
            let s = PigShape.scalar(fat: fat)
            XCTAssertEqual(PigShape.girth(s), s.belly * s.squash, accuracy: 1e-12)
            XCTAssertGreaterThanOrEqual(PigShape.girth(s), s.chest,
                                        "the chest is wider than the reported girth at fat \(fat)")
        }
    }
}
