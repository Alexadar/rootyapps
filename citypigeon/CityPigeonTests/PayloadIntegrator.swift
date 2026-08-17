import Foundation

/// The inverse operator, and the reason this suite is an oracle rather than a mirror.
///
/// `Drop` answers by **solving an equation**. So this file implements the opposite operation with
/// **different mathematics**: it does not solve anything, it *integrates*. Fourth-order Runge-Kutta
/// on `ẍ = 0, ÿ = −g`, stepped until the target plane is crossed on the way down, then bisected to
/// recover the crossing time.
///
/// It knows how a payload falls. It does not know how `Drop` decides. Nothing here reads the engine,
/// and it is deliberately **Foundation-only and `Double`** — MLX has no Float64, so the reference
/// lives on the other side of the boundary from the thing it checks.
///
/// A note on tolerances that the sibling project did not get to make: **RK4 is exact for constant
/// acceleration.** The update reproduces the quadratic identically, so the only error is the
/// bracketing bisection, and 80 halvings is far below double resolution. Disagreement with the
/// closed form is therefore dominated entirely by the engine's Float32, not by this integrator.
struct PayloadIntegrator {

    let gravity: Double
    var dt: Double = 1.0 / 8192.0
    var bisections: Int = 80
    var maxTime: Double = 30.0

    struct State { var x, y, vx, vy: Double }

    private func derivative(_ s: State) -> State {
        State(x: s.vx, y: s.vy, vx: 0, vy: -gravity)
    }

    private func advanced(_ s: State, by h: Double) -> State {
        let k1 = derivative(s)
        let k2 = derivative(offset(s, k1, h / 2))
        let k3 = derivative(offset(s, k2, h / 2))
        let k4 = derivative(offset(s, k3, h))
        return State(x: s.x + h / 6 * (k1.x + 2 * k2.x + 2 * k3.x + k4.x),
                     y: s.y + h / 6 * (k1.y + 2 * k2.y + 2 * k3.y + k4.y),
                     vx: s.vx + h / 6 * (k1.vx + 2 * k2.vx + 2 * k3.vx + k4.vx),
                     vy: s.vy + h / 6 * (k1.vy + 2 * k2.vy + 2 * k3.vy + k4.vy))
    }

    private func offset(_ s: State, _ d: State, _ h: Double) -> State {
        State(x: s.x + d.x * h, y: s.y + d.y * h, vx: s.vx + d.vx * h, vy: s.vy + d.vy * h)
    }

    /// First **descending** crossing of `plane`. Returns nil if the payload never gets there.
    ///
    /// The descending qualifier is the whole point. An upward-launched payload crosses any plane
    /// below its apex twice, and only the second is an impact; accepting the first would certify a
    /// hit the payload reaches on the way up, which is precisely the class of bug the sibling
    /// project's oracle caught on its first run.
    func impact(x0: Double, y0: Double, vx0: Double, u0: Double,
                plane: Double) -> (time: Double, x: Double, vy: Double)? {
        var s = State(x: x0, y: y0, vx: vx0, vy: u0)
        var t = 0.0

        while t < maxTime {
            let next = advanced(s, by: dt)
            let crossedDownward = next.vy < 0 && s.y >= plane && next.y < plane
            if crossedDownward {
                // Bisect inside the bracketing step. Both ends are recomputed from `s` rather than
                // accumulated, so the bisection cannot inherit the step's rounding.
                var lo = 0.0, hi = dt
                for _ in 0..<bisections {
                    let mid = (lo + hi) / 2
                    if advanced(s, by: mid).y >= plane { lo = mid } else { hi = mid }
                }
                let hit = advanced(s, by: (lo + hi) / 2)
                return (t + (lo + hi) / 2, hit.x, hit.vy)
            }
            s = next
            t += dt
        }
        return nil
    }
}
