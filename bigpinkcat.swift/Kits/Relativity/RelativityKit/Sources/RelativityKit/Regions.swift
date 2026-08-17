import Foundation
import TensorKit

/// The regions of a Kerr black hole, as exact radii.
///
/// Pure, stateless. Elementwise over Tensors of matching shape.
///
/// These are not decoration. **Each region is a place where a rule changes**, so this file is the
/// level layout as much as it is physics: outside r₊ you can leave, inside the ergosphere you
/// cannot stand still, between the horizons the radial coordinate is timelike and falling is a date
/// rather than a direction, and past the Cauchy horizon the ring singularity is timelike and
/// therefore avoidable. Every boundary below is a closed form, which is what makes the level
/// geometry oracle-backed rather than art-directed.
///
/// Geometrized units, M = 1, |a| ≤ 1.
public enum Regions {

    /// √(1 − a²), the quantity both horizons are built from. Zero at extremal spin.
    @inline(__always)
    private static func horizonRoot(_ a: Tensor) -> Tensor {
        (1.0 - a * a).sqrtClamped
    }

    /// Outer (event) horizon, r₊ = M + √(M² − a²).
    ///
    /// The one-way surface: nothing sub-light crosses outward. It is precisely because an event
    /// horizon is *defined* by "escape would require exceeding c" that a warp bubble — the standard
    /// model of effective superluminal motion — is the right tool for working inside one, rather
    /// than a hand-wave around it.
    ///
    /// ORACLE: Schwarzschild limit a = 0 gives r₊ = 2M.
    public static func outerHorizon(spin a: Tensor) -> Tensor {
        1.0 + horizonRoot(a)
    }

    /// Inner (Cauchy) horizon, r₋ = M − √(M² − a²).
    ///
    /// The boundary of predictability, and in this game the crossing into the adjacent region. In
    /// the maximal analytic extension of Kerr this is where passage to other asymptotically flat
    /// regions opens; crossing it is otherwise one-way, which is the second reason the bubble is
    /// load-bearing rather than set dressing.
    ///
    /// ORACLE: a = 0 gives r₋ = 0 (Schwarzschild has no inner horizon).
    public static func innerHorizon(spin a: Tensor) -> Tensor {
        1.0 - horizonRoot(a)
    }

    /// Outer boundary of the ergosphere, r_E = M + √(M² − a²cos²θ).
    ///
    /// Between r₊ and r_E no static observer exists: frame dragging is strong enough that *no*
    /// engine can hold you still, yet escape remains possible. That is a workplace with a hazard,
    /// and "you cannot stand still" is a game rule handed over by the metric rather than designed.
    ///
    /// ORACLE: touches r₊ exactly on the axis (θ = 0, π) and reaches 2M in the equatorial plane
    /// for any spin.
    public static func ergosphereOuter(theta: Tensor, spin a: Tensor) -> Tensor {
        let c = theta.cos
        return 1.0 + (1.0 - a * a * c * c).sqrtClamped
    }

    /// Is this point inside the ergosphere? A 0/1 mask, branchless.
    public static func ergosphereMask(r: Tensor, theta: Tensor, spin a: Tensor) -> Tensor {
        let inside = r .< ergosphereOuter(theta: theta, spin: a)
        let outsideHorizon = r .> outerHorizon(spin: a)
        return inside .&& outsideHorizon
    }

    /// Radius of the equatorial circular photon orbit.
    ///
    /// `prograde` co-rotates with the hole and sits closer in; retrograde sits further out. At a = 0
    /// both collapse onto the familiar photon sphere.
    ///
    /// ORACLE: **r_ph = 3M at a = 0** (exactly), **1M prograde / 4M retrograde at a = 1**.
    /// Bardeen, Press & Teukolsky (1972), ApJ 178, 347.
    public static func photonOrbit(spin a: Tensor, prograde: Bool) -> Tensor {
        // r_ph = 2M{1 + cos[(2/3) arccos(∓a/M)]}, upper sign prograde.
        let arg = prograde ? -a : a
        return 2.0 * (1.0 + ((2.0 / 3.0) * arg.acos).cos)
    }

    /// Radius of the innermost stable circular orbit, equatorial.
    ///
    /// The inner edge of anywhere you can park. Below it there is no stable orbit at all, which is
    /// why it is the boundary of the work site rather than an arbitrary one.
    ///
    /// ORACLE: **r_ISCO = 6M at a = 0**, **1M prograde and 9M retrograde at a = 1**.
    /// Bardeen, Press & Teukolsky (1972), ApJ 178, 347, eq. (2.21).
    public static func isco(spin a: Tensor, prograde: Bool) -> Tensor {
        let aa = a * a
        let oneMinus = 1.0 - aa
        // Z₁ = 1 + (1 − a²)^⅓ [ (1 + a)^⅓ + (1 − a)^⅓ ]
        let z1 = 1.0 + oneMinus.cbrt * ((1.0 + a).cbrt + (1.0 - a).cbrt)
        // Z₂ = √(3a² + Z₁²)
        let z2 = (3.0 * aa + z1 * z1).sqrtClamped
        let radical = ((3.0 - z1) * (3.0 + z1 + 2.0 * z2)).sqrtClamped
        return prograde ? (3.0 + z2 - radical) : (3.0 + z2 + radical)
    }

    /// Gravitational redshift factor for a *static* observer, √(1 − 2Mr/Σ).
    ///
    /// Goes to zero on the ergosphere boundary — which is the same statement as "no static observer
    /// exists there", arrived at from the other direction. Inside, use a ZAMO frame instead.
    ///
    /// ORACLE: Schwarzschild limit √(1 − 2M/r); Pound & Rebka (1959) for the weak-field value.
    public static func staticRedshiftFactor(r: Tensor, theta: Tensor, spin a: Tensor) -> Tensor {
        let sig = KerrMetric.sigma(r: r, theta: theta, spin: a)
        return (1.0 - 2.0 * r / sig).sqrtClamped
    }

    /// Angular velocity of a zero-angular-momentum observer, ω = −g_tφ/g_φφ = 2Mar/A.
    ///
    /// This is frame dragging expressed as a rate. Inside the ergosphere it exceeds what any
    /// engine can cancel, and a body with L_z = 0 still acquires dφ/dt = ω. **That is world-space
    /// motion produced by the geometry itself**, not a visual effect over a static world.
    public static func framePickupRate(r: Tensor, theta: Tensor, spin a: Tensor) -> Tensor {
        let bigA = KerrMetric.bigA(r: r, theta: theta, spin: a)
        return 2.0 * a * r / bigA
    }

    /// Which region a point is in. Values match `Region.rawValue`, as a Tensor so it stays vector.
    public static func classify(r: Tensor, theta: Tensor, spin a: Tensor) -> Tensor {
        let rp = outerHorizon(spin: a)
        let rm = innerHorizon(spin: a)
        let re = ergosphereOuter(theta: theta, spin: a)
        // Built up by masked selection rather than branches, outermost first.
        var out = Tensor(repeating: Double(Region.farExterior.rawValue), shape: r.shape)
        out = Tensor.which(r .< 3.0, Double(Region.strongField.rawValue), out)
        out = Tensor.which(r .< re, Double(Region.ergosphere.rawValue), out)
        out = Tensor.which(r .< rp, Double(Region.betweenHorizons.rawValue), out)
        out = Tensor.which(r .< rm, Double(Region.adjacentRegion.rawValue), out)
        return out
    }

    /// The zones, in radial order outward-in. The renderer and the story both key off these.
    public enum Region: Int, CaseIterable, Sendable {
        case farExterior     = 0
        case strongField     = 1
        case ergosphere      = 2
        case betweenHorizons = 3
        case adjacentRegion  = 4
    }
}
