import Testing
import Foundation
@testable import ReachabilityKit

/// THE CENTRE OF THE SUITE.
///
/// The solver maps `geometry → (reachable?, power)`. Here we run the inverse: pick a `(yaw, power,
/// rise)`, ask the RK4 integrator where that jump actually lands, and **put a rooftop there**. Such
/// a roof is reachable by construction — no opinion involved — and the solver's only job is to
/// agree, at the power we used to build it.
///
/// Then the sharp end: place a roof one millimetre beyond where full power lands, and require the
/// solver to say **no**. Reachability is a boolean, so bracketing the envelope from both sides to a
/// millimetre is the strongest statement available about it. A wrong `sin`/`cos`, a wrong `g`, or a
/// lost factor of two cannot survive this test, and none of it restates the implementation.
@Suite("Envelope inversion — construct the answer, then ask the solver")
struct EnvelopeInversionTests {

    let w = WorldConfig.shipping

    private func launchRoof(height: Double = 20) -> Rooftop {
        Rooftop(id: RooftopID(0),
                footprint: Rect2(center: .zero, halfX: 1.2, halfZ: 1.2),
                height: height)
    }

    // MARK: - The forward direction

    @Test("a roof placed where the integrator lands is found reachable at that power",
          arguments: [0.35, 0.5, 0.65, 0.8, 0.9])
    func constructedLandingIsReachable(power: Double) {
        let from = launchRoof()
        for yaw in stride(from: -Double.pi, to: .pi, by: .pi / 6) {
            for rise in [-4.0, -2.0, 0.0, 1.0] {
                guard let to = RoofPlacer.roofAtLanding(
                    from: from, yaw: yaw, power: power, rise: rise,
                    halfExtent: 1.4, id: 1, in: w
                ) else { continue }

                let a = Reachability.assess(from: from, to: to, in: w)
                #expect(a.isReachable,
                        "power \(power), yaw \(yaw), rise \(rise): solver refused a constructed landing")

                if let required = a.requiredPower {
                    // The roof spans a range of distances, so the *minimum* power that reaches it
                    // is at its near edge — never more than the power that put its centre there.
                    #expect(required <= power + 1e-6,
                            "required \(required) exceeded the constructing power \(power)")
                }
            }
        }
    }

    /// The smallest roof that can physically hold a landing at this speed.
    ///
    /// A roof is only usable inward of the frog's own width plus however far it skids, so a target
    /// narrower than that is not a hard target — it is an impossible one, and asking the solver to
    /// certify it tests nothing. (The first draft of this suite used roofs barely wider than the
    /// frog and "failed"; the solver was right and the test was wrong.)
    private func minimumUsableHalfExtent(power: Double, rise: Double) -> Double {
        let v = w.maxLaunchSpeed * power
        guard let impact = Ballistics.impactSpeed(speed: v, rise: rise, in: w) else {
            return w.frogHalfWidth
        }
        return Ballistics.landingInset(impact: impact, in: w)
    }

    @Test("required power recovers the constructing power for a near-pinpoint target")
    func requiredPowerRecoversConstructingPower() {
        // Shrink the roof to the smallest thing that can actually be landed on, so "the near edge"
        // and "the centre" are nearly the same point and the recovered power must match what built
        // it. Any smaller and the frog would skid off the far side.
        let from = launchRoof()
        for power in stride(from: 0.4, through: 0.9, by: 0.1) {
            let half = minimumUsableHalfExtent(power: power, rise: 0) + 0.02
            guard let to = RoofPlacer.roofAtLanding(
                from: from, yaw: 0.7, power: power, rise: 0, halfExtent: half, id: 1, in: w
            ) else { continue }
            let a = Reachability.assess(from: from, to: to, in: w)
            guard a.isReachable, let required = a.requiredPower else {
                Issue.record("power \(power): not reachable")
                continue
            }
            // The usable patch is centred on where the jump lands, so the least power that reaches
            // it is a touch under the constructing power — by about the patch's own half-width.
            #expect(required <= power + 1e-6, "power \(power): recovered \(required)")
            #expect(required > power - 0.12, "power \(power): recovered \(required)")
        }
    }

    // MARK: - The boundary sandwich

    @Test("a roof one millimetre inside full power is reachable, and one millimetre beyond is not")
    func boundarySandwich() {
        // The sharpest statement this suite makes, and deliberately framed so that **no modelling
        // choice can blur it**. The envelope's outer edge is located by the RK4 integrator — nothing
        // from `Ballistics` decides where it is — and then:
        //
        //   * a roof centred exactly on that landing point must be reachable;
        //   * a roof whose *entire footprint* begins one millimetre past it must not be.
        //
        // The second is unfalsifiable by any landing-tolerance model: the inset only ever shrinks
        // the usable part of a roof, so if even the roof's nearest edge is beyond what the frog can
        // physically reach, no tolerance can rescue it. (An earlier version of this test placed the
        // roof by its *usable* edge, which meant the test and the solver had to agree about the
        // inset's fixed point — and they disagreed by 0.3% of power. That made the test a
        // restatement of the implementation, which is exactly what this file exists to avoid.)
        let from = launchRoof()
        let ceiling = w.powerCeiling
        let delta = 0.001    // one millimetre

        for yaw in stride(from: -Double.pi, to: .pi, by: .pi / 4) {
            for rise in [-3.0, 0.0, 1.0] {
                let half = minimumUsableHalfExtent(power: ceiling, rise: rise) + 0.15

                guard let inside = RoofPlacer.roofAtLanding(
                    from: from, yaw: yaw, power: ceiling, rise: rise,
                    halfExtent: half, id: 1, nudgeAlongYaw: 0, in: w
                ), let beyond = RoofPlacer.roofAtLanding(
                    from: from, yaw: yaw, power: ceiling, rise: rise,
                    halfExtent: half, id: 2, nudgeAlongYaw: half + delta, in: w
                ) else { continue }

                #expect(Reachability.assess(from: from, to: inside, in: w).isReachable,
                        "yaw \(yaw), rise \(rise): refused a roof inside the envelope")
                #expect(!Reachability.assess(from: from, to: beyond, in: w).isReachable,
                        "yaw \(yaw), rise \(rise): certified a roof beyond the envelope")
            }
        }
    }

    // MARK: - Routes by construction

    @Test("a route built by walking the envelope is found by the solver, and decoys never are")
    func constructedRouteIsFoundAndDecoysAreNot() {
        var roofs = [launchRoof()]
        var rng = SplitMix64(seed: 20260810)
        let chainLength = 5

        // Walk a chain of landings we know are reachable, because we placed each one where the
        // integrator says the previous jump ends. A sampled (power, rise) pair can be physically
        // impossible — climbing costs range, so a low-power jump simply cannot gain much height —
        // so each link resamples until the integrator reports an actual landing.
        // Roofs must not overlap each other. Real districts cannot produce overlapping rooftops
        // (`ConfigConsistencyTests` proves the lattice forbids it), and overlapping ones here would
        // make the obstacle test fire on buildings that are inside one another — a property of the
        // fixture, not of the solver.
        let half = 0.5
        func overlapsExisting(_ candidate: Rooftop) -> Bool {
            roofs.contains { existing in
                abs(existing.footprint.center.x - candidate.footprint.center.x) < half * 2.4 &&
                abs(existing.footprint.center.z - candidate.footprint.center.z) < half * 2.4
            }
        }

        for i in 1...chainLength {
            let previous = roofs.last!
            for _ in 0..<64 {
                let yaw = rng.double(in: (-Double.pi)...Double.pi)
                let power = rng.double(in: 0.6...0.85)
                let rise = rng.double(in: (-1.5)...0.3)
                guard let next = RoofPlacer.roofAtLanding(
                    from: previous, yaw: yaw, power: power, rise: rise,
                    halfExtent: half, id: i, in: w
                ) else { continue }
                if overlapsExisting(next) { continue }
                roofs.append(next)
                break
            }
        }
        guard roofs.count == chainLength + 1 else {
            Issue.record("could not construct the chain")
            return
        }

        // Decoys: placed strictly past what full power reaches from every roof in the chain.
        var decoys: [Rooftop] = []
        for (i, r) in roofs.enumerated() {
            guard let decoy = RoofPlacer.roofAtLanding(
                from: r, yaw: 2.4, power: w.powerCeiling, rise: 0,
                halfExtent: 1.0, id: 100 + i, nudgeAlongYaw: 3.0, in: w
            ) else { continue }
            decoys.append(decoy)
        }

        let block = CityBlock(
            seed: 1, districtIndex: 0, rooftops: roofs + decoys,
            spawn: RooftopID(0), goal: RooftopID(chainLength),
            flyRoofs: [], killPlaneY: 0
        )
        let graph = ReachabilityGraph(block: block, config: w)

        // (a) the constructed route exists, and is no longer than the chain we built
        guard let route = graph.route(from: block.spawn, to: block.goal) else {
            Issue.record("solver could not find the constructed route")
            return
        }
        #expect(route.jumpCount <= chainLength)

        // (b) every link we built is an edge the solver agrees with
        for i in 0..<chainLength {
            let a = graph.assessment(from: RooftopID(i), to: RooftopID(i + 1))
            #expect(a.isReachable, "constructed link \(i) → \(i + 1) was not an edge")
        }

        // (c) no decoy is ever an edge from the roof it was placed beyond
        for (i, decoy) in decoys.enumerated() {
            let a = graph.assessment(from: RooftopID(i), to: decoy.id)
            #expect(!a.isReachable, "decoy \(decoy.id) was reachable from roof \(i)")
        }
    }
}
