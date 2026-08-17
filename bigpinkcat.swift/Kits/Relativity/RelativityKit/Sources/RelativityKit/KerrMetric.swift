import Foundation
import TensorKit

/// The Kerr metric in Boyer–Lindquist coordinates, and its first derivatives.
///
/// Pure, stateless. Elementwise over Tensors of matching shape — hand it `[1]` for one body or
/// `[N, R]` for a sweep and it is the same code.
///
/// **Geometrized units: G = c = M = 1.** The hole's mass is the unit of length and time, so the
/// outer horizon sits at r ≈ 1–2, the photon sphere at 3 and the ISCO at 6. Every quantity the
/// integrator touches is O(1), which keeps the arithmetic clear of denormals and conditions the ODE
/// better than SI would.
///
/// Spin `a` is dimensionless in these units and must satisfy |a| ≤ 1; a = 0 recovers Schwarzschild
/// and |a| = 1 is extremal. Beyond 1 there is no horizon — a naked singularity — which is a
/// different spacetime, not a harder case, so it is a `precondition` and not a clamp.
///
/// ORACLES: Boyer & Lindquist (1967), *Maximal Analytic Extension of the Kerr Metric*, J. Math.
/// Phys. 8, 265. Misner, Thorne & Wheeler §33 for the inverse-metric components.
public enum KerrMetric {

    /// Σ = r² + a²cos²θ. Vanishes only on the ring singularity (r = 0, θ = π/2).
    public static func sigma(r: Tensor, theta: Tensor, spin a: Tensor) -> Tensor {
        let c = theta.cos
        return r * r + a * a * c * c
    }

    /// Δ = r² − 2Mr + a², with M = 1. Vanishes at the horizons; negative between them.
    public static func delta(r: Tensor, spin a: Tensor) -> Tensor {
        r * r - 2.0 * r + a * a
    }

    /// A = (r² + a²)² − a²Δsin²θ. The lapse-like quantity in g^tt.
    public static func bigA(r: Tensor, theta: Tensor, spin a: Tensor) -> Tensor {
        let s = theta.sin
        let d = delta(r: r, spin: a)
        let rr = r * r + a * a
        return rr * rr - a * a * d * s * s
    }

    /// The five non-zero inverse-metric components, plus their ∂/∂r and ∂/∂θ.
    ///
    /// Returned together because the geodesic right-hand side needs all fifteen at once and
    /// recomputing Σ, Δ and their derivatives three times over is the difference between a sweep
    /// that runs and one that does not.
    ///
    /// The derivatives are **analytic**, not finite differences. A finite difference would be
    /// deterministic too, but its O(h²) error shows up directly as drift in the Carter constant —
    /// and the Carter constant is the oracle. Degrading the oracle to save algebra is the wrong
    /// trade.
    public struct Inverse {
        public let gtt, gtp, gpp, grr, gthth: Tensor
        public let dr_gtt, dr_gtp, dr_gpp, dr_grr, dr_gthth: Tensor
        public let dth_gtt, dth_gtp, dth_gpp, dth_grr, dth_gthth: Tensor
    }

    public static func inverse(r: Tensor, theta: Tensor, spin a: Tensor) -> Inverse {
        let s = theta.sin
        let c = theta.cos
        let s2 = s * s
        let aa = a * a

        let sig = r * r + aa * c * c
        let del = r * r - 2.0 * r + aa
        let r2a2 = r * r + aa
        let bigA = r2a2 * r2a2 - aa * del * s2

        // Partials of the building blocks.
        let dsig_dr = 2.0 * r
        let dsig_dth = -2.0 * aa * c * s          // ∂(a²cos²θ)/∂θ
        let ddel_dr = 2.0 * r - 2.0
        // ∂Δ/∂θ = 0.
        let dA_dr = 4.0 * r * r2a2 - aa * s2 * ddel_dr
        let dA_dth = -aa * del * (2.0 * s * c)

        let sd = sig * del                        // Σ Δ, the common denominator
        let dsd_dr = dsig_dr * del + sig * ddel_dr
        let dsd_dth = dsig_dth * del

        // g^tt = -A / (ΣΔ)
        let gtt = -bigA / sd
        let dr_gtt = -(dA_dr * sd - bigA * dsd_dr) / (sd * sd)
        let dth_gtt = -(dA_dth * sd - bigA * dsd_dth) / (sd * sd)

        // g^tφ = -2 a r / (ΣΔ)      (M = 1)
        let num_tp = -2.0 * a * r
        let dnum_tp_dr = -2.0 * a
        let gtp = num_tp / sd
        let dr_gtp = (dnum_tp_dr * sd - num_tp * dsd_dr) / (sd * sd)
        let dth_gtp = (-num_tp * dsd_dth) / (sd * sd)

        // g^φφ = (Δ - a²sin²θ) / (Σ Δ sin²θ)
        let num_pp = del - aa * s2
        let den_pp = sd * s2
        let dnum_pp_dr = ddel_dr
        let dnum_pp_dth = -aa * (2.0 * s * c)
        let dden_pp_dr = dsd_dr * s2
        let dden_pp_dth = dsd_dth * s2 + sd * (2.0 * s * c)
        let gpp = num_pp / den_pp
        let dr_gpp = (dnum_pp_dr * den_pp - num_pp * dden_pp_dr) / (den_pp * den_pp)
        let dth_gpp = (dnum_pp_dth * den_pp - num_pp * dden_pp_dth) / (den_pp * den_pp)

        // g^rr = Δ / Σ
        let grr = del / sig
        let dr_grr = (ddel_dr * sig - del * dsig_dr) / (sig * sig)
        let dth_grr = (-del * dsig_dth) / (sig * sig)

        // g^θθ = 1 / Σ
        let gthth = 1.0 / sig
        let dr_gthth = -dsig_dr / (sig * sig)
        let dth_gthth = -dsig_dth / (sig * sig)

        return Inverse(gtt: gtt, gtp: gtp, gpp: gpp, grr: grr, gthth: gthth,
                       dr_gtt: dr_gtt, dr_gtp: dr_gtp, dr_gpp: dr_gpp,
                       dr_grr: dr_grr, dr_gthth: dr_gthth,
                       dth_gtt: dth_gtt, dth_gtp: dth_gtp, dth_gpp: dth_gpp,
                       dth_grr: dth_grr, dth_gthth: dth_gthth)
    }
}
