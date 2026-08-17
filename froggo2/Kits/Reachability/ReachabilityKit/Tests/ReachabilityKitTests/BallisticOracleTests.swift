import Testing
import Foundation
@testable import ReachabilityKit

/// The closed form, tested as IDENTITIES and ORDERINGS rather than as remembered numbers.
///
/// Almost nothing here asserts a literal. A literal expectation is a second copy of the
/// implementation written by the same hand; an identity (`f⁻¹(f(x)) == x`), an ordering
/// (`down > flat > up`), or an agreement with an independent integrator are claims the
/// implementation cannot satisfy by being consistently wrong.
@Suite("Ballistics — identities and orderings")
struct BallisticOracleTests {

    let w = WorldConfig.shipping

    // MARK: - Inverses

    @Test("range and requiredSpeed are exact inverses", arguments: [0.2, 0.35, 0.5, 0.7, 0.9, 1.0])
    func rangeAndSpeedInvert(power: Double) {
        for rise in stride(from: -6.0, through: 3.0, by: 1.5) {
            let v = w.maxLaunchSpeed * power
            guard let d = Ballistics.range(speed: v, rise: rise, in: w) else { continue }
            guard let back = Ballistics.requiredSpeed(range: d, rise: rise, in: w) else {
                Issue.record("range gave \(d) but requiredSpeed refused it (rise \(rise))")
                continue
            }
            #expect(abs(back - v) < 1e-9, "rise \(rise): \(back) vs \(v)")
        }
    }

    @Test("requiredSpeed and range are exact inverses the other way round")
    func speedAndRangeInvert() {
        for rise in stride(from: -6.0, through: 3.0, by: 1.0) {
            for d in stride(from: 2.0, through: 14.0, by: 1.0) {
                guard let v = Ballistics.requiredSpeed(range: d, rise: rise, in: w) else { continue }
                guard let back = Ballistics.range(speed: v, rise: rise, in: w) else {
                    Issue.record("requiredSpeed gave \(v) but range refused it (d \(d), rise \(rise))")
                    continue
                }
                // Right at `d·tanθ = 2h` the ascending and descending crossings merge into a double
                // root, the discriminant is zero, and recovering d from v is genuinely
                // ill-conditioned — a square root of a cancelling difference. The tolerance is
                // widened only in that neighbourhood, and only because the mathematics says so.
                let slack = d * tan(w.launchElevation) - 2 * rise
                let tolerance = slack < 0.5 ? 1e-6 : 1e-9
                #expect(abs(back - d) < tolerance, "d \(d), rise \(rise): got \(back)")
            }
        }
    }

    /// Regression for a bug this suite caught on its first run.
    ///
    /// `requiredSpeed` originally solved `h(d) = h` without asking *which* of the two crossings it
    /// had found. For an uphill target it happily returned the speed whose **ascending** branch
    /// passed through the roof — a jump that flies over the roof and lands well beyond it. The
    /// solver would have certified routes the player could not fly, which is the exact failure the
    /// oracle exists to prevent, and no hand-written expected value would have exposed it.
    @Test("a landing is never certified on the ascending branch")
    func ascendingBranchIsRejected() {
        let θ = w.launchElevation
        for rise in stride(from: 0.5, through: 3.0, by: 0.5) {
            let boundary = Ballistics.minimumLandingDistance(rise: rise, in: w)

            // Just inside the ascending branch: the arc is still climbing here.
            let tooClose = boundary * 0.9
            #expect(Ballistics.requiredSpeed(range: tooClose, rise: rise, in: w) == nil,
                    "rise \(rise): accepted an ascending-branch landing at \(tooClose)")

            // Just past it: a real landing, and the round trip holds.
            let landable = boundary * 1.3
            guard let v = Ballistics.requiredSpeed(range: landable, rise: rise, in: w) else {
                Issue.record("rise \(rise): refused a legitimate landing at \(landable)")
                continue
            }
            let back = Ballistics.range(speed: v, rise: rise, in: w)
            #expect(back != nil && abs(back! - landable) < 1e-7, "rise \(rise)")

            // And the frog really is descending when it arrives.
            let t = landable / (v * cos(θ))
            let verticalSpeed = v * sin(θ) - w.gravity * t
            #expect(verticalSpeed < 0, "rise \(rise): frog was still climbing on arrival")
        }
    }

    @Test("the integrator agrees about where landings become possible")
    func integratorConfirmsTheLandingBoundary() {
        // Independent confirmation that `minimumLandingDistance` is real rather than a convenient
        // guard: RK4 stepped to the first DESCENDING crossing never lands closer than it.
        for rise in stride(from: 0.5, through: 3.0, by: 0.5) {
            let boundary = Ballistics.minimumLandingDistance(rise: rise, in: w)
            for power in stride(from: 0.25, through: 1.0, by: 0.05) {
                guard let hit = TrajectoryIntegrator.horizontalDistance(
                    speed: w.maxLaunchSpeed * power, elevation: w.launchElevation,
                    gravity: w.gravity, targetRise: rise
                ) else { continue }
                #expect(hit.distance >= boundary - 1e-6,
                        "rise \(rise), power \(power): landed at \(hit.distance), boundary \(boundary)")
            }
        }
    }

    // MARK: - Agreement with the independent integrator

    @Test("the closed form agrees with RK4 integration", arguments: [0.3, 0.55, 0.8, 1.0])
    func closedFormMatchesIntegrator(power: Double) {
        let v = w.maxLaunchSpeed * power
        for rise in stride(from: -5.0, through: 2.0, by: 1.0) {
            guard let closed = Ballistics.range(speed: v, rise: rise, in: w),
                  let integrated = TrajectoryIntegrator.horizontalDistance(
                      speed: v, elevation: w.launchElevation, gravity: w.gravity, targetRise: rise
                  ) else { continue }
            // Two different mathematics: solving a quadratic vs. stepping a differential equation.
            #expect(abs(closed - integrated.distance) < 1e-4,
                    "power \(power), rise \(rise): closed \(closed) vs integrated \(integrated.distance)")
        }
    }

    @Test("flight time agrees with the integrator")
    func flightTimeMatchesIntegrator() {
        let v = w.maxLaunchSpeed * 0.75
        guard let closed = Ballistics.flightTime(speed: v, rise: 0, in: w),
              let integrated = TrajectoryIntegrator.horizontalDistance(
                  speed: v, elevation: w.launchElevation, gravity: w.gravity, targetRise: 0
              ) else { Issue.record("no solution"); return }
        #expect(abs(closed - integrated.time) < 1e-4)
    }

    // MARK: - Textbook identities

    @Test("flat range is v²·sin(2θ)/g")
    func flatRangeIsTextbook() {
        let v = w.maxLaunchSpeed
        let expected = v * v * sin(2 * w.launchElevation) / w.gravity
        #expect(abs(Ballistics.range(speed: v, rise: 0, in: w)! - expected) < 1e-9)
    }

    @Test("energy is conserved along the arc")
    func energyConserved() {
        let v = w.maxLaunchSpeed * 0.8
        let total = 0.5 * v * v
        let hang = 2 * v * sin(w.launchElevation) / w.gravity
        for i in 0...20 {
            let t = hang * Double(i) / 20
            let p = Ballistics.position(speed: v, yaw: 0, t: t, in: w)
            let vy = v * sin(w.launchElevation) - w.gravity * t
            let vx = v * cos(w.launchElevation)
            let energy = 0.5 * (vx * vx + vy * vy) + w.gravity * p.y
            #expect(abs(energy - total) < 1e-9, "at t=\(t)")
        }
    }

    @Test("45 degrees maximises flat range")
    func fortyFiveIsOptimal() {
        // Proves the elevation choice instead of asserting it.
        var best = (angle: 0.0, range: 0.0)
        for degrees in stride(from: 5.0, through: 85.0, by: 0.5) {
            var probe = w
            probe.launchElevation = degrees * .pi / 180
            let r = Ballistics.range(speed: w.maxLaunchSpeed, rise: 0, in: probe) ?? 0
            if r > best.range { best = (degrees, r) }
        }
        #expect(abs(best.angle - 45.0) < 0.6, "best was \(best.angle)°")
    }

    // MARK: - Monotonicity

    @Test("range strictly increases with speed")
    func rangeIncreasesWithSpeed() {
        for rise in [-4.0, -1.0, 0.0, 1.5] {
            var previous = -Double.infinity
            for power in stride(from: 0.15, through: 1.0, by: 0.05) {
                guard let d = Ballistics.range(speed: w.maxLaunchSpeed * power, rise: rise, in: w)
                else { continue }
                #expect(d > previous, "rise \(rise), power \(power)")
                previous = d
            }
        }
    }

    @Test("required speed increases with both distance and rise")
    func requiredSpeedIsMonotone() {
        var previous = -Double.infinity
        for d in stride(from: 2.0, through: 12.0, by: 0.5) {
            let v = Ballistics.requiredSpeed(range: d, rise: 0, in: w)!
            #expect(v > previous)
            previous = v
        }
        previous = -Double.infinity
        for rise in stride(from: -5.0, through: 2.0, by: 0.5) {
            let v = Ballistics.requiredSpeed(range: 8, rise: rise, in: w)!
            #expect(v > previous, "rise \(rise)")
            previous = v
        }
    }

    // MARK: - The fly

    @Test("the fly multiplies range by the square of its speed bonus")
    func flyScalesRangeQuadratically() {
        let base = Ballistics.range(speed: w.maxLaunchSpeed, rise: 0, in: w)!
        let boosted = Ballistics.range(speed: w.maxLaunchSpeed * w.flyMultiplier, rise: 0, in: w)!
        // Froggo 1's 1.5× on impulse is 1.5× on velocity, and range goes as v² — so 2.25×.
        // This is the number that turns the fly from "a longer jump" into "a different route".
        #expect(abs(boosted / base - w.flyMultiplier * w.flyMultiplier) < 1e-9)
    }

    // MARK: - Degenerate inputs

    @Test("zero power reaches nowhere")
    func zeroPowerReachesNowhere() {
        #expect(Ballistics.range(speed: 0, rise: 0, in: w) == nil)
    }

    @Test("the two reasons a jump is refused are distinct and both hold")
    func refusalReasonsAreDistinct() {
        let d = 5.0
        let θ = w.launchElevation
        let onRay = d * tan(θ)          // the straight launch ray at this distance

        // (1) Above the launch ray: unreachable at any speed, because the arc only ever falls away
        //     from that ray. This is the height ceiling.
        #expect(Ballistics.requiredSpeed(range: d, rise: onRay + 0.1, in: w) == nil)

        // (2) Below the ray but above half of it: a speed exists that passes through the point, but
        //     while still climbing — so it is not a landing. Refused for a different reason.
        #expect(Ballistics.requiredSpeed(range: d, rise: onRay * 0.75, in: w) == nil)

        // (3) Below half the ray: a genuine landing on the descending branch.
        #expect(Ballistics.requiredSpeed(range: d, rise: onRay * 0.25, in: w) != nil)

        // The boundary between (2) and (3) is exactly d·tanθ = 2h.
        #expect(abs(Ballistics.minimumLandingDistance(rise: onRay * 0.5, in: w) - d) < 1e-12)
    }
}
