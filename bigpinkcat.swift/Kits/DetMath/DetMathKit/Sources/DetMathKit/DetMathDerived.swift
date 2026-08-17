import Foundation

/// Functions derived from the primitives in `DetMath`, using only `+ - * /`, `squareRoot()` and
/// the fixed-coefficient kernels. No libm, so they inherit bit-identical behaviour for free.
extension DetMath {

    /// Arc cosine, in [0, π].
    ///
    /// `acos(x) = atan2(√(1 - x²), x)`. This is an *identity*, not an approximation — so the whole
    /// function costs one square root on top of `atan2`, and needs no coefficient table of its own.
    /// It is also better conditioned near |x| = 1 than the `atan(√(1-x²)/x)` form, which loses the
    /// quadrant.
    public static func acos(_ x: Double) -> Double {
        if x.isNaN { return .nan }
        // Clamp: a value a hair outside [-1, 1] here is rounding in the caller's dot product, not a
        // bug, and returning NaN for cos θ = 1.0000000000000002 would be actively unhelpful.
        let c = x > 1 ? 1.0 : (x < -1 ? -1.0 : x)
        return atan2(sqrtClamped(1 - c * c), c)
    }

    /// Arc sine, in [-π/2, π/2]. `asin(x) = atan2(x, √(1 - x²))`.
    public static func asin(_ x: Double) -> Double {
        if x.isNaN { return .nan }
        let c = x > 1 ? 1.0 : (x < -1 ? -1.0 : x)
        return atan2(c, sqrtClamped(1 - c * c))
    }

    /// Real cube root, deterministic.
    ///
    /// `pow(x, 1.0/3.0)` would be a libm call and is on the ban list; it is also wrong for negative
    /// x. Instead: a seed from exponent division on the bit pattern, then a **fixed** number of
    /// Newton steps. Fixed is the operative word — an iterate-until-converged loop would terminate
    /// after a different number of steps on a different target and reintroduce exactly the
    /// divergence this package exists to remove.
    ///
    /// Newton on y³ = x gives y ← (2y + x/y²)/3, which converges quadratically; the bit-hack seed
    /// is good to ~5%, so five steps reach full double precision with margin.
    public static func cbrt(_ x: Double) -> Double {
        if x == 0 || !x.isFinite { return x }
        let negative = x < 0
        let a = negative ? -x : x

        // Seed: dividing the biased exponent by three approximates the cube root of the magnitude.
        // The additive constant re-biases the exponent after the division.
        var bits = a.bitPattern
        bits = bits / 3 &+ 0x2a9f_7893_782d_ad30
        var y = Double(bitPattern: bits)

        // Fixed five Newton steps. Never `while |y³ - a| > eps`.
        for _ in 0..<5 {
            y = (2.0 * y + a / (y * y)) / 3.0
        }
        return negative ? -y : y
    }
}
