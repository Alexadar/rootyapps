import XCTest
import TensorKit
import DetMathKit
import RelativityKit

/// The cross-target half of the determinism contract.
///
/// This suite lives in the **app target** rather than in a Kit, and that is the whole point: the app
/// target builds for macOS, the iOS Simulator and a device, so running it on each is what proves the
/// simulation produces identical bits everywhere. A Kit-only test runs on one architecture and
/// proves nothing about portability.
///
/// Two independent checks, because they catch different failures:
///
///   * **the hash** catches "this machine produced different numbers than that machine" — a
///     portability bug, invisible to any physics assertion;
///   * **conservation** catches "the integrator is drifting" — a correctness bug, invisible to the
///     hash, because a drifting integrator drifts identically everywhere.
///
/// If a golden below fails on a new platform, do NOT update the constant. Find out which operation
/// diverged: it will be a banned call that slipped in, an FMA contraction, or a libm transcendental
/// reached directly instead of through DetMath.
final class DeterminismGoldenTests: XCTestCase {

    /// Canonical scenarios. Fixed inputs, fixed step, fixed count — nothing here may read a clock.
    private struct Scenario {
        let name: String
        let spin: Double
        let impactParameter: Double
        let steps: Int
        let golden: UInt64
    }

    /// Goldens recorded on arm64 macOS 14, Xcode 26.5 SDK, release configuration.
    private let scenarios: [Scenario] = [
        .init(name: "kerr-a0.8-b7-500", spin: 0.8, impactParameter: 7, steps: 500,
              golden: 0x794e5fff18c28509),
    ]

    private func trajectory(spin: Double, b: Double, steps: Int) -> [Tensor] {
        let a = Tensor(shape: [1], data: [spin])
        let y0 = InitialConditions.fromConstants(
            r: Tensor(shape: [1], data: [25]),
            theta: Tensor(shape: [1], data: [DetMath.halfPi]),
            phi: Tensor(shape: [1], data: [0]),
            t: Tensor(shape: [1], data: [0]),
            energy: Tensor(shape: [1], data: [1]),
            axialAngularMomentum: Tensor(shape: [1], data: [b]),
            pTheta: Tensor(shape: [1], data: [0]),
            spin: a, restMass: Tensor(shape: [1], data: [0]), outward: false)
        return Geodesic.integrateRecording(y0, spin: a,
                                           dLambda: Tensor(shape: [1], data: [0.01]), steps: steps)
    }

    func testTrajectoryHashesMatchTheGoldens() {
        for s in scenarios {
            var h = DeterminismHash()
            for state in trajectory(spin: s.spin, b: s.impactParameter, steps: s.steps) {
                h.absorb(state.data)
            }
            XCTAssertEqual(h.digest, s.golden, """
                \(s.name): trajectory hash diverged.
                got \(h) — expected \(String(format: "%016llx", s.golden)).
                Do NOT update the golden. Find the operation that differs: a banned call, an FMA
                contraction, or a libm transcendental reached outside DetMath.
                """)
        }
    }

    func testTheSameScenarioHashesIdenticallyTwiceInAProcess() {
        // Catches accidental state: a cached buffer, a static that mutates, a lazily-initialised
        // table that differs on second use.
        let s = scenarios[0]
        var a = DeterminismHash(), b = DeterminismHash()
        for st in trajectory(spin: s.spin, b: s.impactParameter, steps: s.steps) { a.absorb(st.data) }
        for st in trajectory(spin: s.spin, b: s.impactParameter, steps: s.steps) { b.absorb(st.data) }
        XCTAssertEqual(a, b, "the integrator is carrying state between runs")
    }

    func testConservationHoldsOnThisPlatform() {
        // The physics-level check, run on every destination. Bits agreeing is not enough — they
        // could agree on a wrong answer.
        let a = Tensor(shape: [1], data: [0.8])
        let mu = Tensor(shape: [1], data: [0])
        let states = trajectory(spin: 0.8, b: 7, steps: 500)
        let drift = Invariants.drift(from: states.first!, to: states.last!, spin: a, restMass: mu)
        XCTAssertEqual(drift.energy.data[0], 0, accuracy: 0, "E is conserved bit-exactly")
        XCTAssertEqual(drift.axialAngularMomentum.data[0], 0, accuracy: 0, "L_z bit-exactly")
        XCTAssertLessThan(drift.carter.data[0], 1e-9, "Carter constant on this platform")
        XCTAssertLessThan(drift.massShell.data[0], 1e-9, "mass shell on this platform")
    }

    func testDeterministicTranscendentalsAgreeWithTheirGoldens() {
        // A drifting libm would show up here before it showed up as a trajectory divergence, and
        // with a far shorter path to the cause.
        var h = DeterminismHash()
        for i in 0..<512 {
            let x = -8.0 + 16.0 * Double(i) / 511.0
            h.absorb(DetMath.sin(x)); h.absorb(DetMath.cos(x)); h.absorb(DetMath.atan(x))
        }
        // RECORDED on arm64 macOS 14 / Xcode 26.5, not authored. A golden is a measurement of what
        // this code actually produces; inventing the constant and then "fixing" it when it fails
        // inverts the test into a tautology. The first draft of this line did exactly that.
        XCTAssertEqual(h.digest, 0xcaf152a99a43bdaf, """
            DetMath transcendentals diverged on this platform: \(h).
            This is the first thing to check when a trajectory golden fails.
            """)
    }
}
