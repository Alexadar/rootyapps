import XCTest
import TensorKit
@testable import PortalKit

/// ORACLES for portals are structural rather than published — a portal is a human invention, so
/// there is no journal to cite. What replaces a citation is that each expected value is fixed by a
/// *definition* rather than by what the code emits:
///
///   * **round-trip identity** — going through a pair and back must compose to I, exactly;
///   * **isometry** — a portal may not create or destroy speed, so ‖v‖ is preserved;
///   * **designed holonomy** — a non-euclidean loop must impart the rotation the level design
///     specifies, and that number comes from the design document.
final class PortalOracleTests: XCTestCase {

    private func t(_ v: Double, _ n: Int = 1) -> Tensor { Tensor(repeating: v, shape: [n]) }

    /// A portal at `(x,y,z)` facing +Z, up +Y.
    private func portalFacingZ(x: Double, y: Double, z: Double, n: Int = 1) -> Tensor {
        Portal.frame(centerX: t(x, n), centerY: t(y, n), centerZ: t(z, n),
                     forwardX: t(0, n), forwardY: t(0, n), forwardZ: t(1, n),
                     upX: t(0, n), upY: t(1, n), upZ: t(0, n))
    }

    /// A portal facing +X.
    private func portalFacingX(x: Double, y: Double, z: Double, n: Int = 1) -> Tensor {
        Portal.frame(centerX: t(x, n), centerY: t(y, n), centerZ: t(z, n),
                     forwardX: t(1, n), forwardY: t(0, n), forwardZ: t(0, n),
                     upX: t(0, n), upY: t(1, n), upZ: t(0, n))
    }

    private func point(_ x: Double, _ y: Double, _ z: Double) -> Tensor {
        Tensor(shape: [1, 4], data: [x, y, z, 1])
    }

    // MARK: - Frames

    func testFrameIsOrthonormal() {
        // If the basis is not orthonormal, every downstream guarantee — isometry, round-trip
        // identity, momentum preservation — is false by an amount nobody notices.
        let m = portalFacingX(x: 3, y: -2, z: 7)
        let c = m.reshaped([1, 16]).unstackLast().map { $0.data[0] }
        let right = (c[0], c[4], c[8])
        let up = (c[1], c[5], c[9])
        let fwd = (c[2], c[6], c[10])
        func dot(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
            a.0 * b.0 + a.1 * b.1 + a.2 * b.2
        }
        XCTAssertEqual(dot(right, right), 1, accuracy: 1e-14, "right is unit")
        XCTAssertEqual(dot(up, up), 1, accuracy: 1e-14, "up is unit")
        XCTAssertEqual(dot(fwd, fwd), 1, accuracy: 1e-14, "forward is unit")
        XCTAssertEqual(dot(right, up), 0, accuracy: 1e-14, "right ⟂ up")
        XCTAssertEqual(dot(right, fwd), 0, accuracy: 1e-14, "right ⟂ forward")
        XCTAssertEqual(dot(up, fwd), 0, accuracy: 1e-14, "up ⟂ forward")
    }

    func testRigidInverseIsAnActualInverse() {
        let m = portalFacingX(x: 5, y: 1, z: -3)
        let composed = Tensor.matmul4x4(m, Portal.invertRigid(m))
        XCTAssertEqual(Portal.deviationFromIdentity(composed).data[0], 0, accuracy: 1e-14,
                       "M · M⁻¹ = I")
    }

    // MARK: - The round-trip identity

    func testGoingThroughAPairAndBackIsTheIdentity() {
        // The defining property. A→B composed with B→A must be exactly I: anything else means an
        // object that loops through a portal pair slowly drifts, rotates or grows.
        let a = portalFacingZ(x: 0, y: 0, z: 0)
        let b = portalFacingX(x: 10, y: 4, z: -6)
        let there = Portal.transform(source: a, destination: b)
        let back = Portal.transform(source: b, destination: a)
        let loop = Tensor.matmul4x4(back, there)
        XCTAssertEqual(Portal.deviationFromIdentity(loop).data[0], 0, accuracy: 1e-13,
                       "A→B→A must compose to the identity")
    }

    func testRoundTripHoldsForAWholeBatchOfPairs() {
        // 64 differently placed pairs at once — the shape a level sweep uses.
        let n = 64
        let xs = (0..<n).map { Double($0) * 0.37 - 10 }
        let a = Portal.frame(centerX: Tensor(shape: [n], data: xs), centerY: t(2, n), centerZ: t(-1, n),
                             forwardX: t(0, n), forwardY: t(0, n), forwardZ: t(1, n),
                             upX: t(0, n), upY: t(1, n), upZ: t(0, n))
        let b = Portal.frame(centerX: t(4, n), centerY: Tensor(shape: [n], data: xs), centerZ: t(9, n),
                             forwardX: t(1, n), forwardY: t(0, n), forwardZ: t(0, n),
                             upX: t(0, n), upY: t(1, n), upZ: t(0, n))
        let loop = Tensor.matmul4x4(Portal.transform(source: b, destination: a),
                                    Portal.transform(source: a, destination: b))
        let dev = Portal.deviationFromIdentity(loop)
        XCTAssertLessThan(dev.maxLast().data[0], 1e-12, "worst round-trip deviation across 64 pairs")
    }

    // MARK: - Isometry

    func testPortalPreservesSpeed() {
        // A portal transports; it must not accelerate. If ‖v‖ changed, a loop of portals would be a
        // free energy source, which is both bad physics and an exploitable game bug.
        let a = portalFacingZ(x: 0, y: 0, z: 0)
        let b = portalFacingX(x: 7, y: 2, z: 1)
        let tm = Portal.transform(source: a, destination: b)
        let v = Tensor(shape: [1, 4], data: [0.3, -1.7, 2.2, 0])
        let mask = t(1)
        let out = Portal.rotateVector(v, transform: tm, mask: mask)
        func norm(_ x: Tensor) -> Double {
            let c = x.unstackLast()
            return (c[0].data[0] * c[0].data[0] + c[1].data[0] * c[1].data[0]
                    + c[2].data[0] * c[2].data[0]).squareRoot()
        }
        XCTAssertEqual(norm(out), norm(v), accuracy: 1e-13, "speed is preserved through a portal")
    }

    // MARK: - Crossing, branchlessly

    func testNewlyCrossedFiresExactlyOnceOnTheTransition() {
        // The froggo2 edge-detect rule. It must fire on the tick the sign flips and never again
        // while the entity stays through.
        let before = Tensor(shape: [4], data: [ 1.0,  1.0, -1.0, -1.0])
        let after  = Tensor(shape: [4], data: [ 1.0, -1.0, -1.0,  1.0])
        let newly = Portal.newlyCrossed(distanceNow: after, distancePrevious: before)
        XCTAssertEqual(newly.data, [0, 1, 0, 0],
                       "fires only where the sign went + → −: not for staying out, staying in, or leaving")
    }

    func testTeleportIsMaskedAndLeavesNonCrossersBitIdentical()  {
        let a = portalFacingZ(x: 0, y: 0, z: 0, n: 2)
        let b = portalFacingX(x: 10, y: 0, z: 0, n: 2)
        let tm = Portal.transform(source: a, destination: b)
        let pts = Tensor(shape: [2, 4], data: [1, 2, 3, 1,
                                               4, 5, 6, 1])
        let mask = Tensor(shape: [2], data: [1, 0])
        let out = Portal.teleport(points: pts, transform: tm, mask: mask)
        // The unmasked entity must come back untouched, to the bit — not "close enough".
        XCTAssertEqual(Array(out.data[4..<8]), [4, 5, 6, 1],
                       "an entity that did not cross is returned bit-identical")
        XCTAssertNotEqual(Array(out.data[0..<4]), [1, 2, 3, 1], "the crosser moved")
    }

    func testSignedDistanceIsPositiveInFront() {
        let p = portalFacingZ(x: 0, y: 0, z: 0)
        XCTAssertGreaterThan(Portal.signedDistance(points: point(0, 0, 5), frame: p).data[0], 0,
                             "in front of the portal")
        XCTAssertLessThan(Portal.signedDistance(points: point(0, 0, -5), frame: p).data[0], 0,
                          "behind it")
        XCTAssertEqual(Portal.signedDistance(points: point(3, 4, 0), frame: p).data[0], 0,
                       accuracy: 1e-14, "on the plane, however far off-axis")
    }

    // MARK: - Holonomy

    func testLoopParity() {
        // **Portal loops close only for an EVEN number of hops**, and that is geometry rather than
        // a quirk of this implementation. Each hop carries one `flip`, and since
        //
        //     A→B→C→A  =  (P_A f P_C⁻¹)(P_C f P_B⁻¹)(P_B f P_A⁻¹)  =  P_A f³ P_A⁻¹  =  P_A f P_A⁻¹
        //
        // an odd loop retains exactly one half-turn no matter how the portals are placed. The first
        // version of this test asserted a three-hop loop was the identity and measured 2√2 — which
        // is precisely ‖diag(−1,1,−1,1) − I‖_F, i.e. the leftover flip, not an error.
        //
        // Level design consequence: a corridor of portals that must leave the player upright needs
        // an even number of mouths.
        let a = portalFacingZ(x: 0, y: 0, z: 0)
        let b = portalFacingX(x: 5, y: 0, z: 0)
        let c = portalFacingZ(x: 5, y: 5, z: 5)
        let ab = Portal.transform(source: a, destination: b)
        let bc = Portal.transform(source: b, destination: c)
        let ca = Portal.transform(source: c, destination: a)

        let odd = Portal.holonomy([ab, bc, ca])
        XCTAssertEqual(Portal.deviationFromIdentity(odd).data[0], 2.0 * 2.0.squareRoot(),
                       accuracy: 1e-12,
                       "a three-hop loop retains exactly one half-turn: ‖f − I‖_F = 2√2")

        // Going round twice — six hops, an even number — restores the identity exactly.
        let even = Portal.holonomy([ab, bc, ca, ab, bc, ca])
        XCTAssertEqual(Portal.deviationFromIdentity(even).data[0], 0, accuracy: 1e-12,
                       "two laps of an odd loop close exactly")
    }

    func testDesignedHolonomyIsMeasuredAgainstTheDesign() {
        // The non-euclidean case. Two portals whose frames disagree by a deliberate quarter turn:
        // a lap must impart exactly that quarter turn, and the expected value comes from the level
        // design, never from running the code and writing down the answer.
        let a = portalFacingZ(x: 0, y: 0, z: 0)
        let b = portalFacingX(x: 0, y: 0, z: 0)   // same place, rotated 90° about Y
        let loop = Portal.holonomy([Portal.transform(source: a, destination: b)])
        let deviation = Portal.deviationFromIdentity(loop).data[0]
        XCTAssertGreaterThan(deviation, 0.1, "a quarter-turn stitch must NOT be the identity")

        // Four laps of a quarter turn is a full turn, which IS the identity again.
        let quarter = Portal.transform(source: a, destination: b)
        let fourLaps = Portal.holonomy([quarter, quarter, quarter, quarter])
        XCTAssertEqual(Portal.deviationFromIdentity(fourLaps).data[0], 0, accuracy: 1e-12,
                       "four quarter turns compose back to the identity")
    }
}
