import Foundation
import DetMathKit

/// The vector face of DetMathKit.
///
/// **This is the API domain code uses. The scalar `DetMath.sin(Double)` is a kernel, not an
/// interface.** A polynomial evaluation is inherently per-element, so something has to be scalar at
/// the bottom — but that something lives here, inside `map`/`zip`, in exactly the same place the
/// loops live. Domain code writes `theta.sin`; it never writes `DetMath.sin(theta[i])`, and
/// `VectorDisciplineTests` fails the build if it does.
///
/// Everything below is deterministic: fixed-coefficient approximations over the five IEEE-754
/// operations that are correctly rounded. No libm, ever.
extension Tensor {

    /// Elementwise sine. Radians.
    public var sin: Tensor { map(DetMath.sin) }

    /// Elementwise cosine. Radians.
    public var cos: Tensor { map(DetMath.cos) }

    /// Elementwise tangent. Radians.
    public var tan: Tensor { map(DetMath.tan) }

    /// Elementwise arctangent, principal value in (-π/2, π/2).
    public var atan: Tensor { map(DetMath.atan) }

    /// Elementwise two-argument arctangent, in (-π, π].
    ///
    /// Shapes must match exactly — there is no implicit broadcasting anywhere in this type. Use the
    /// `expanded*` family to make a broadcast explicit, which keeps the shape algebra readable at
    /// the call site instead of hidden in an operator.
    public static func atan2(_ y: Tensor, _ x: Tensor) -> Tensor {
        zip(y, x, DetMath.atan2)
    }

    /// Elementwise arc cosine, in [0, π]. Arguments a hair outside [-1, 1] are clamped — that is
    /// rounding in the caller's dot product, not a bug.
    public var acos: Tensor { map(DetMath.acos) }

    /// Elementwise arc sine, in [-π/2, π/2].
    public var asin: Tensor { map(DetMath.asin) }

    /// Elementwise real cube root, valid for negative arguments.
    public var cbrt: Tensor { map(DetMath.cbrt) }

    /// Elementwise √x with negatives clamped to zero.
    ///
    /// For quantities that can go a hair negative purely by rounding at a turning point — a radial
    /// velocity at periapsis, say. Where a negative would mean a real bug, assert instead.
    public var sqrtClamped: Tensor { map(DetMath.sqrtClamped) }
}
