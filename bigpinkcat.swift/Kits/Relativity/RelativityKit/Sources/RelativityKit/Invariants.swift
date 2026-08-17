import Foundation
import TensorKit

/// The conserved quantities of Kerr geodesic motion — the free, infinitely reusable oracle.
///
/// Pure, stateless. Elementwise over Tensors of matching shape.
///
/// Carter (1968) proved the Hamilton–Jacobi equation separates in Kerr, which makes geodesic motion
/// **completely integrable**: four constants (E, L_z, the Carter constant Q, and the rest mass μ)
/// determine every orbit, and the equations reduce to quadratures. The practical consequence for
/// this project is large — **every trajectory the engine produces, generated or authored, carries
/// four quantities that must not change.** No one has to author an expected value; the physics
/// supplies the assertion.
///
/// Two of the four are conserved *structurally* by the Hamiltonian integrator (see `Geodesic`), so
/// they test the state plumbing rather than the integrator. Q and the mass shell are the ones that
/// genuinely test the integrator, because nothing in its construction forces them.
///
/// ORACLES: Carter, B. (1968), Phys. Rev. 174, 1559. Misner, Thorne & Wheeler §33.5.
public enum Invariants {

    /// Energy at infinity, E = −p_t. Conserved because the metric is stationary.
    public static func energy(_ y: Tensor) -> Tensor {
        -y.unstackLast()[Geodesic.S.pt]
    }

    /// Axial angular momentum, L_z = p_φ. Conserved because the metric is axisymmetric.
    public static func axialAngularMomentum(_ y: Tensor) -> Tensor {
        y.unstackLast()[Geodesic.S.pphi]
    }

    /// The Carter constant,
    ///
    ///   Q = p_θ² + cos²θ [ a²(μ² − E²) + L_z²/sin²θ ]
    ///
    /// It arises from a second-order Killing tensor — a *hidden* symmetry with no corresponding
    /// coordinate translation — which is why it cannot be conserved by construction the way E and
    /// L_z are, and why it is the sharpest available test of the integrator.
    ///
    /// `restMass` is 0 for photons and >0 for matter; it is the only difference between the two.
    public static func carter(_ y: Tensor, spin a: Tensor, restMass mu: Tensor) -> Tensor {
        let c = y.unstackLast()
        let th = c[Geodesic.S.theta]
        let pth = c[Geodesic.S.ptheta]
        let e = -c[Geodesic.S.pt]
        let lz = c[Geodesic.S.pphi]

        let cosT = th.cos
        let sinT = th.sin
        // Guarded away from the polar axis, where the Boyer–Lindquist chart itself is singular and
        // L_z²/sin²θ diverges. A trajectory that reaches the axis exactly has left the chart, not
        // the spacetime.
        let s2 = (sinT * sinT).maximum(1e-300)
        return pth * pth + cosT * cosT * (a * a * (mu * mu - e * e) + lz * lz / s2)
    }

    /// The mass shell, g^{μν} p_μ p_ν. Equals −μ²: zero for photons, negative for matter.
    ///
    /// The most direct statement of "is this still a geodesic of the right kind". A photon whose
    /// mass shell has drifted off zero is no longer travelling at the speed of light, which is a
    /// bug the Carter constant will not necessarily catch.
    public static func massShell(_ y: Tensor, spin a: Tensor) -> Tensor {
        let c = y.unstackLast()
        let g = KerrMetric.inverse(r: c[Geodesic.S.r], theta: c[Geodesic.S.theta], spin: a)
        let pt = c[Geodesic.S.pt], pr = c[Geodesic.S.pr]
        let pth = c[Geodesic.S.ptheta], pp = c[Geodesic.S.pphi]
        return g.gtt * pt * pt
            + 2.0 * g.gtp * pt * pp
            + g.gpp * pp * pp
            + g.grr * pr * pr
            + g.gthth * pth * pth
    }

    /// All four at once, which is how the test suites want them.
    public struct Set: Sendable {
        public let energy: Tensor
        public let axialAngularMomentum: Tensor
        public let carter: Tensor
        public let massShell: Tensor
    }

    public static func all(_ y: Tensor, spin a: Tensor, restMass mu: Tensor) -> Set {
        Set(energy: energy(y),
            axialAngularMomentum: axialAngularMomentum(y),
            carter: carter(y, spin: a, restMass: mu),
            massShell: massShell(y, spin: a))
    }

    /// Largest absolute drift in each invariant between two states, as a `[..]`-shaped Tensor each.
    ///
    /// Relative would be the friendlier number, but several of these legitimately pass through zero
    /// — Q vanishes for equatorial orbits, L_z for polar ones, the mass shell for every photon —
    /// and a relative error against zero is a division by zero dressed up as rigour.
    public static func drift(from y0: Tensor, to y1: Tensor,
                             spin a: Tensor, restMass mu: Tensor) -> Set {
        let s0 = all(y0, spin: a, restMass: mu)
        let s1 = all(y1, spin: a, restMass: mu)
        return Set(energy: (s1.energy - s0.energy).absolute,
                   axialAngularMomentum: (s1.axialAngularMomentum - s0.axialAngularMomentum).absolute,
                   carter: (s1.carter - s0.carter).absolute,
                   massShell: (s1.massShell - s0.massShell).absolute)
    }
}

/// Building physically valid initial conditions.
///
/// Getting a geodesic started is the one genuinely fiddly part of the API: you cannot pick eight
/// numbers freely, because the mass shell constrains them. These helpers solve that constraint so
/// callers never hand the integrator a state that is not on any geodesic at all.
public enum InitialConditions {

    /// A photon (or particle) launched from `(r, θ)` with given E, L_z and p_θ, with p_r solved
    /// from the mass-shell condition g^{μν}p_μp_ν = −μ².
    ///
    /// `outward` picks the branch: the constraint is quadratic in p_r and both roots are physical,
    /// one moving in and one out.
    ///
    /// Returns state `[.., 8]`. Where the radicand is negative there is no real p_r — the requested
    /// (E, L_z, Q) is not attainable at that radius, i.e. the point lies inside the orbit's
    /// forbidden region — and p_r is clamped to zero, which places the launch exactly at a turning
    /// point rather than producing a NaN that poisons the whole sweep.
    public static func fromConstants(r: Tensor, theta: Tensor, phi: Tensor, t: Tensor,
                                     energy e: Tensor, axialAngularMomentum lz: Tensor,
                                     pTheta pth: Tensor, spin a: Tensor, restMass mu: Tensor,
                                     outward: Bool) -> Tensor {
        let g = KerrMetric.inverse(r: r, theta: theta, spin: a)
        let pt = -e
        // g^rr p_r² = −μ² − [ g^tt p_t² + 2 g^tφ p_t p_φ + g^φφ p_φ² + g^θθ p_θ² ]
        let rest = g.gtt * pt * pt
            + 2.0 * g.gtp * pt * lz
            + g.gpp * lz * lz
            + g.gthth * pth * pth
        let pr2 = (-(mu * mu) - rest) / g.grr
        let pr = pr2.sqrtClamped
        return Geodesic.state(t: t, r: r, theta: theta, phi: phi,
                              pt: pt, pr: outward ? pr : -pr, ptheta: pth, pphi: lz)
    }
}
