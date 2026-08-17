import Foundation

/// Deterministic transcendental functions with fixed coefficients.
///
/// Pure, stateless. Every function here is a polynomial or rational evaluation over `+ - * /` and
/// `Double.squareRoot()` — the five operations IEEE-754 requires to be correctly rounded — so the
/// result is bit-identical on every conforming target, today and after any OS update.
///
/// ORACLES: coefficients are transcribed from **FDLIBM** (Sun Microsystems, 1993, public domain —
/// `__kernel_sin`, `__kernel_cos`) and the **Cephes Math Library** (Stephen L. Moshier, `atan.c`).
/// Both are published, citable sources. Nothing here is fitted by us, in keeping with
/// `docs/calculators_VALIDATION.md`: the implementation comes from one place and the numbers from
/// another.
///
/// MODEL CAVEAT: these are minimax/Taylor approximations, not correctly-rounded implementations.
/// They agree with a good libm to within a few ulp, which is far tighter than any physical
/// tolerance in this game, and — the property that matters — they agree with *themselves* exactly,
/// everywhere.
public enum DetMath {

    // MARK: - Constants

    public static let pi        = 3.14159265358979311600e+00
    public static let twoPi     = 6.28318530717958623200e+00
    public static let halfPi    = 1.57079632679489655800e+00
    public static let quarterPi = 7.85398163397448278999e-01

    /// π/2 split into a head with its low 33 bits clear and an exact tail, so that
    /// `x - n*PIO2_HI - n*PIO2_LO` loses far less precision than subtracting a single rounded π/2.
    /// This is Cody–Waite range reduction; the constants are FDLIBM's `pio2_1` and `pio2_1t`.
    private static let pio2Hi = 1.57079632673412561417e+00
    private static let pio2Lo = 6.07710050650619224932e-11
    /// 2/π, for computing the quadrant index.
    private static let twoOverPi = 6.36619772367581382433e-01

    // MARK: - sine and cosine
    //
    // FDLIBM `__kernel_sin` / `__kernel_cos` coefficients, valid on |x| <= π/4.

    private static let S1 = -1.66666666666666324348e-01
    private static let S2 =  8.33333333332248946124e-03
    private static let S3 = -1.98412698298579493134e-04
    private static let S4 =  2.75573137070700676789e-06
    private static let S5 = -2.50507602534068634195e-08
    private static let S6 =  1.58969099521155010221e-10

    private static let C1 =  4.16666666666666019037e-02
    private static let C2 = -1.38888888888741095749e-03
    private static let C3 =  2.48015872894767294178e-05
    private static let C4 = -2.75573143513906633035e-07
    private static let C5 =  2.08757232129817482790e-09
    private static let C6 = -1.13596475577881948265e-11

    /// sin(x) for |x| <= π/4. Odd polynomial in x, degree 13.
    @inline(__always)
    private static func kernelSin(_ x: Double) -> Double {
        let z = x * x
        let r = S2 + z * (S3 + z * (S4 + z * (S5 + z * S6)))
        return x + x * z * (S1 + z * r)
    }

    /// cos(x) for |x| <= π/4. Even polynomial in x, degree 14.
    @inline(__always)
    private static func kernelCos(_ x: Double) -> Double {
        let z = x * x
        let r = z * z * (C1 + z * (C2 + z * (C3 + z * (C4 + z * (C5 + z * C6)))))
        // The 1 - z/2 head is written split so the cancellation for x near π/4 stays benign,
        // exactly as FDLIBM does it.
        let hz = 0.5 * z
        let w = 1.0 - hz
        return w + ((1.0 - w) - hz + r)
    }

    /// Reduce `x` to `(quadrant, y)` with |y| <= π/4 and x ≈ quadrant·(π/2) + y.
    ///
    /// `rint`-free and branch-light: the quadrant is obtained by rounding x·(2/π) to nearest via the
    /// add-magic-subtract-magic trick, which is exact for |n| < 2^52 and — unlike `rint` — does not
    /// depend on the current floating-point rounding mode being left alone by some other framework.
    @inline(__always)
    private static func reduce(_ x: Double) -> (q: Int, y: Double) {
        let fn = x * twoOverPi
        // Round to nearest, ties away from zero. Deterministic and mode-independent.
        let n = (fn >= 0) ? Double(Int64(fn + 0.5)) : Double(Int64(fn - 0.5))
        let y = (x - n * pio2Hi) - n * pio2Lo
        // Swift's % on a negative Int64 keeps the sign; normalise into 0..<4.
        let q = ((Int(n) % 4) + 4) % 4
        return (q, y)
    }

    /// Deterministic sine. Radians.
    public static func sin(_ x: Double) -> Double {
        guard x.isFinite else { return .nan }
        let (q, y) = reduce(x)
        switch q {
        case 0:  return kernelSin(y)
        case 1:  return kernelCos(y)
        case 2:  return -kernelSin(y)
        default: return -kernelCos(y)
        }
    }

    /// Deterministic cosine. Radians.
    public static func cos(_ x: Double) -> Double {
        guard x.isFinite else { return .nan }
        let (q, y) = reduce(x)
        switch q {
        case 0:  return kernelCos(y)
        case 1:  return -kernelSin(y)
        case 2:  return -kernelCos(y)
        default: return kernelSin(y)
        }
    }

    /// Deterministic tangent. Radians.
    ///
    /// Computed as sin/cos rather than by its own kernel: one fewer coefficient table to keep
    /// honest, and the geodesic integrator never evaluates it near a pole (θ is guarded away from
    /// the axis, where the Boyer–Lindquist chart is singular anyway).
    public static func tan(_ x: Double) -> Double {
        let c = cos(x)
        return c == 0 ? .infinity : sin(x) / c
    }

    // MARK: - arctangent
    //
    // Cephes `atan.c` rational approximation, degree 4 over degree 5 (with an implicit leading 1),
    // valid after reduction onto [0, tan(π/8)].

    private static let P0 = -8.750608600031904122785e-01
    private static let P1 = -1.615753718733365076637e+01
    private static let P2 = -7.500855792314704667340e+01
    private static let P3 = -1.228866684490136173410e+02
    private static let P4 = -6.485021904942025371773e+01

    private static let Q0 =  2.485846490142306297962e+01
    private static let Q1 =  1.650270098316988542046e+02
    private static let Q2 =  4.328810604912902668951e+02
    private static let Q3 =  4.853903996359136964868e+02
    private static let Q4 =  1.945506571482613964425e+02

    /// tan(3π/8) and tan(π/8) — the two reduction thresholds.
    private static let tan3Pi8 = 2.41421356237309504880e+00
    private static let tanPi8  = 0.41421356237309504880e+00
    /// The residual of π/4 beyond its double rounding, added back after reduction (Cephes `morebits`).
    private static let moreBits = 6.123233995736765886130e-17

    /// Deterministic arctangent, principal value in (-π/2, π/2).
    public static func atan(_ x: Double) -> Double {
        guard x.isFinite else {
            if x.isNaN { return .nan }
            return x > 0 ? halfPi : -halfPi
        }
        let sign = x < 0
        var a = sign ? -x : x

        // Reduce onto [0, tan(π/8)], remembering which constant head we owe back.
        var y: Double
        let flag: Int
        if a > tan3Pi8 {
            y = halfPi
            flag = 1
            a = -1.0 / a
        } else if a > tanPi8 {
            y = quarterPi
            flag = 2
            a = (a - 1.0) / (a + 1.0)
        } else {
            y = 0.0
            flag = 0
        }

        let z = a * a
        let num = ((((P0 * z + P1) * z + P2) * z + P3) * z + P4) * z
        let den = ((((z + Q0) * z + Q1) * z + Q2) * z + Q3) * z + Q4
        y = y + (num / den) * a + a

        // `halfPi` and `quarterPi` are themselves rounded doubles; moreBits is the residual owed
        // back, and Cephes keys it off the reduction branch taken — never off the result.
        if flag == 1 { y += moreBits }
        else if flag == 2 { y += 0.5 * moreBits }

        return sign ? -y : y
    }

    /// Deterministic two-argument arctangent, in (-π, π].
    ///
    /// Sign and quadrant handling is exact — only the underlying `atan` is approximate — so the
    /// discontinuity at the branch cut lands in exactly the same place on every target.
    public static func atan2(_ y: Double, _ x: Double) -> Double {
        if x.isNaN || y.isNaN { return .nan }
        // `x.sign`, not `x >= 0` — the latter is true for -0.0, which must yield π, not 0.
        if y == 0 { return x.sign == .plus ? 0 : pi }
        if x == 0 { return y > 0 ? halfPi : -halfPi }
        let a = atan(y / x)
        if x > 0 { return a }
        return y > 0 ? a + pi : a - pi
    }

    // MARK: - Safe helpers
    //
    // `squareRoot()` is hardware `fsqrt` and correctly rounded, so it needs no replacement — but a
    // domain guard does belong here, because a negative under the root in the geodesic integrator
    // means a state that has left the physical region, and silently producing NaN hides it.

    /// √x, or 0 for x < 0. Use where a tiny negative can only be rounding at a turning point.
    @inline(__always)
    public static func sqrtClamped(_ x: Double) -> Double {
        x <= 0 ? 0 : x.squareRoot()
    }

    /// √x, trapping on a negative argument. Use where a negative means a real bug.
    @inline(__always)
    public static func sqrtChecked(_ x: Double) -> Double {
        precondition(x >= 0, "sqrtChecked on negative argument \(x)")
        return x.squareRoot()
    }
}
