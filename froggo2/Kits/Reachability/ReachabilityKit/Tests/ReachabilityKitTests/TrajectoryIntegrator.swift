import Foundation
@testable import ReachabilityKit

/// THE INVERSE OPERATOR — the thing that makes this suite an oracle rather than a restatement.
///
/// `ReachabilityKit` answers "given this geometry, is it reachable and at what power?" It answers it
/// by *solving an equation*: rearranging the trajectory for `v`, and comparing intervals.
///
/// A test that hand-writes "roof at 8.4 m with a 1 m rise should need 0.62 power" proves nothing —
/// the same person decided both the expectation and the implementation, and any shared
/// misunderstanding is invisible to both. So this file implements the *opposite* operation with
/// *different mathematics*: it does not solve anything, it **integrates**. Fourth-order Runge-Kutta
/// on `ẍ = 0, ÿ = −g`, stepped until the target plane is crossed, then bisected to find the crossing.
///
/// It knows how a frog flies. It does not know how the solver decides. Nothing here reads
/// `Ballistics`. When the two agree at 1e-9 across a swept grid, that agreement is evidence, because
/// a closed form and a numerical integrator can only both be wrong by coincidence.
///
/// (Same doctrine as `gridscan/Kits/Stitch/.../StitchOracleTests.swift`, which builds a page
/// *splitter* to test a page *stitcher*.)
enum TrajectoryIntegrator {

    struct State {
        var x: Double      // horizontal distance travelled
        var y: Double      // height above launch
        var vx: Double
        var vy: Double
    }

    static func derivative(_ s: State, gravity g: Double) -> State {
        State(x: s.vx, y: s.vy, vx: 0, vy: -g)
    }

    static func step(_ s: State, dt: Double, gravity g: Double) -> State {
        func add(_ a: State, _ b: State, _ scale: Double) -> State {
            State(x: a.x + b.x * scale, y: a.y + b.y * scale,
                  vx: a.vx + b.vx * scale, vy: a.vy + b.vy * scale)
        }
        let k1 = derivative(s, gravity: g)
        let k2 = derivative(add(s, k1, dt / 2), gravity: g)
        let k3 = derivative(add(s, k2, dt / 2), gravity: g)
        let k4 = derivative(add(s, k3, dt), gravity: g)
        let slope = State(
            x: (k1.x + 2 * k2.x + 2 * k3.x + k4.x) / 6,
            y: (k1.y + 2 * k2.y + 2 * k3.y + k4.y) / 6,
            vx: (k1.vx + 2 * k2.vx + 2 * k3.vx + k4.vx) / 6,
            vy: (k1.vy + 2 * k2.vy + 2 * k3.vy + k4.vy) / 6
        )
        return add(s, slope, dt)
    }

    /// Integrate until the descending arc crosses `targetRise`, returning how far it went.
    /// `nil` if the apex never reaches the target plane.
    static func horizontalDistance(speed v: Double, elevation θ: Double, gravity g: Double,
                                   targetRise h: Double,
                                   dt: Double = 1.0 / 8192) -> (distance: Double, time: Double)? {
        var s = State(x: 0, y: 0, vx: v * cos(θ), vy: v * sin(θ))
        var t = 0.0
        var previous = s
        var previousT = 0.0

        // Bound the walk generously: far beyond any real flight time at these speeds.
        let limit = 60.0
        while t < limit {
            previous = s
            previousT = t
            s = step(s, dt: dt, gravity: g)
            t += dt

            // Only accept a crossing on the way down, and only after the apex.
            if s.vy < 0 && previous.y >= h && s.y < h {
                // Bisect between the two straddling states.
                var lo = previousT, hi = t
                for _ in 0..<80 {
                    let mid = (lo + hi) / 2
                    var probe = previous
                    probe = step(previous, dt: mid - previousT, gravity: g)
                    if probe.y >= h { lo = mid } else { hi = mid }
                }
                var landed = previous
                landed = step(previous, dt: (lo + hi) / 2 - previousT, gravity: g)
                return (landed.x, (lo + hi) / 2)
            }
            if s.y < h - 1e6 { return nil }
        }
        return nil
    }
}

/// Places a rooftop exactly where a jump lands, according to the integrator.
///
/// This is the production-grade version of "construct the answer, then ask the solver to find it".
/// A roof built this way is reachable *by construction*, and the solver's job is to agree.
enum RoofPlacer {
    static func roofAtLanding(from origin: Rooftop, yaw: Double, power: Double,
                              rise: Double, halfExtent: Double, id: Int,
                              nudgeAlongYaw: Double = 0,
                              in w: WorldConfig) -> Rooftop? {
        let v = w.maxLaunchSpeed * power
        guard let hit = TrajectoryIntegrator.horizontalDistance(
            speed: v, elevation: w.launchElevation, gravity: w.gravity, targetRise: rise
        ) else { return nil }

        let d = hit.distance + nudgeAlongYaw
        guard d > 0 else { return nil }
        let dir = Vec2.direction(yaw: yaw)
        let centre = origin.footprint.center + dir * d

        return Rooftop(
            id: RooftopID(id),
            footprint: Rect2(center: centre, halfX: halfExtent, halfZ: halfExtent),
            height: origin.height + rise
        )
    }
}
