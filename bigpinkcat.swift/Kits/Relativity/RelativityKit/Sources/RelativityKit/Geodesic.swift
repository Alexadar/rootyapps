import Foundation
import TensorKit

/// Geodesic motion in Kerr spacetime, in Hamiltonian form.
///
/// Pure, stateless. Elementwise over Tensors of matching shape: `[1]` solves one worldline, `[N, R]`
/// solves a sweep, and it is the same code.
///
/// **This is the world, not a picture of it.** Light and matter both integrate here. A photon is a
/// null geodesic (p·p = 0), the cosmonaut and every loose object are timelike geodesics
/// (p·p = −μ²) — one mass-shell parameter apart, one code path. That is why frame dragging actually
/// moves bodies rather than merely bending the view, and why the conserved-quantity oracle
/// validates the rendering and the gameplay at the same time.
///
/// # State layout
///
/// `[.., 8]` — `(t, r, θ, φ, p_t, p_r, p_θ, p_φ)`. Position is contravariant xᵘ; momentum is
/// **covariant** p_μ, and that choice is the reason this integrator conserves anything:
///
///   * the metric is stationary ⇒ ∂H/∂t = 0 ⇒ **dp_t/dλ ≡ 0**, so E = −p_t is conserved *exactly*,
///     to the last bit, structurally rather than numerically;
///   * the metric is axisymmetric ⇒ ∂H/∂φ = 0 ⇒ **dp_φ/dλ ≡ 0**, so L_z = p_φ likewise.
///
/// Only the Carter constant and the mass shell are left to drift, which makes them a genuinely
/// independent check on the integrator instead of a restatement of its construction.
///
/// ORACLES: Carter (1968), *Global Structure of the Kerr Family of Gravitational Fields*, Phys. Rev.
/// 174, 1559 — the Hamilton–Jacobi equation separates, geodesic motion is completely integrable, and
/// a fourth constant exists. Misner, Thorne & Wheeler §33.5 for the Hamiltonian form.
public enum Geodesic {

    /// Index of each component within the trailing axis of the state tensor.
    public enum S {
        public static let t = 0, r = 1, theta = 2, phi = 3
        public static let pt = 4, pr = 5, ptheta = 6, pphi = 7
        public static let count = 8
    }

    /// Assemble a state tensor from its eight components, each of shape `[..]`.
    public static func state(t: Tensor, r: Tensor, theta: Tensor, phi: Tensor,
                             pt: Tensor, pr: Tensor, ptheta: Tensor, pphi: Tensor) -> Tensor {
        Tensor.stackLast([t, r, theta, phi, pt, pr, ptheta, pphi])
    }

    /// The Hamiltonian right-hand side, dy/dλ, for state `[.., 8]`.
    ///
    /// H = ½ g^{μν} p_μ p_ν, so
    ///   dxᵘ/dλ = ∂H/∂p_μ = g^{μν} p_ν
    ///   dp_μ/dλ = −∂H/∂xᵘ = −½ (∂_μ g^{αβ}) p_α p_β
    ///
    /// No loop over trajectories anywhere: every line below is elementwise over the whole batch.
    public static func derivative(_ y: Tensor, spin a: Tensor) -> Tensor {
        let c = y.unstackLast()
        let r = c[S.r], th = c[S.theta]
        let pt = c[S.pt], pr = c[S.pr], pth = c[S.ptheta], pp = c[S.pphi]

        let g = KerrMetric.inverse(r: r, theta: th, spin: a)

        // dxᵘ/dλ = g^{μν} p_ν
        let dt   = g.gtt * pt + g.gtp * pp
        let dr   = g.grr * pr
        let dth  = g.gthth * pth
        let dphi = g.gtp * pt + g.gpp * pp

        // dp_t/dλ and dp_φ/dλ are identically zero — the two Killing vectors. Written as explicit
        // zeros rather than omitted, so the shape algebra stays uniform and the reason stays visible.
        let zero = Tensor(repeating: 0, shape: r.shape)

        // dp_r/dλ = −½ ∂_r g^{αβ} p_α p_β
        let dpr = -0.5 * (g.dr_gtt * pt * pt
                          + 2.0 * g.dr_gtp * pt * pp
                          + g.dr_gpp * pp * pp
                          + g.dr_grr * pr * pr
                          + g.dr_gthth * pth * pth)

        // dp_θ/dλ = −½ ∂_θ g^{αβ} p_α p_β
        let dpth = -0.5 * (g.dth_gtt * pt * pt
                           + 2.0 * g.dth_gtp * pt * pp
                           + g.dth_gpp * pp * pp
                           + g.dth_grr * pr * pr
                           + g.dth_gthth * pth * pth)

        return Tensor.stackLast([dt, dr, dth, dphi, zero, dpr, dpth, zero])
    }

    /// One classical RK4 step of fixed size `dLambda`.
    ///
    /// Fixed, not adaptive, and deliberately: an adaptive controller that halts on a tolerance takes
    /// a different number of sub-steps on a different target and reintroduces exactly the divergence
    /// the determinism contract exists to remove. Where variable resolution is genuinely needed, use
    /// `step(_:spin:dLambda:)` with a `dLambda` that is itself a pure function of state — see
    /// `stepSizePolicy` — so the schedule is reproducible from the state alone.
    public static func step(_ y: Tensor, spin a: Tensor, dLambda h: Tensor) -> Tensor {
        let h8 = h.expandedLast(S.count)
        let k1 = derivative(y, spin: a)
        let k2 = derivative(y + h8 * 0.5 * k1, spin: a)
        let k3 = derivative(y + h8 * 0.5 * k2, spin: a)
        let k4 = derivative(y + h8 * k3, spin: a)
        return y + (h8 / 6.0) * (k1 + 2.0 * k2 + 2.0 * k3 + k4)
    }

    /// A deterministic step-size policy: a pure function of state, never of a tolerance loop.
    ///
    /// Steps shrink near the horizon and near the ring, where the chart stiffens, and open up far
    /// away. Because it reads only `r`, two machines starting from the same state take *the same
    /// schedule*, which is what keeps the trajectory hash stable.
    ///
    /// MODEL CAVEAT: this controls resolution, not accuracy. It does not make the integrator
    /// symplectic, and it does not rescue a trajectory that has entered a chaotic region — near the
    /// photon sphere and past the Cauchy horizon only *topological* outcomes (escaped, crossed,
    /// which region) are assertable, never exact paths.
    public static func stepSizePolicy(r: Tensor, spin a: Tensor, base: Double = 1.0 / 32.0) -> Tensor {
        let rp = Regions.outerHorizon(spin: a)
        // Distance above the horizon, floored so the policy stays finite where the chart does not.
        let above = (r - rp).maximum(1.0 / 1024.0)
        let scale = (above / (1.0 + above)).minimum(1.0)
        return base * scale
    }

    /// Integrate `steps` fixed RK4 steps, returning only the final state.
    ///
    /// The step count is an `Int` and the loop is bounded algorithmic depth — one of the three
    /// places `VectorDisciplineTests` allows a loop, alongside the primitive kernels and boundary
    /// marshalling. It is the analogue of torchsim's time loop: every trajectory in the batch
    /// advances together, inside it.
    public static func integrate(_ y0: Tensor, spin a: Tensor,
                                 dLambda h: Tensor, steps: Int) -> Tensor {
        precondition(steps >= 0, "negative step count")
        var y = y0
        for _ in 0..<steps { y = step(y, spin: a, dLambda: h) }
        return y
    }

    /// Integrate, recording the state after every step. Returns `steps + 1` states including `y0`.
    ///
    /// For trajectory hashing and for the renderer's worldline buffers. The array is a boundary
    /// marshalling concern, not domain logic.
    public static func integrateRecording(_ y0: Tensor, spin a: Tensor,
                                          dLambda h: Tensor, steps: Int) -> [Tensor] {
        var out: [Tensor] = [y0]
        out.reserveCapacity(steps + 1)
        var y = y0
        for _ in 0..<steps {
            y = step(y, spin: a, dLambda: h)
            out.append(y)
        }
        return out
    }
}
