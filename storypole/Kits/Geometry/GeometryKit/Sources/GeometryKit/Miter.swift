import Foundation

/// Miter and compound (crown) angle math. Pure, stateless.
///
/// Oracle class: IDENTITY, matched against published crown-molding tables —
/// spring 38° → (miter 31.62°, bevel 33.86°), spring 45° → (35.26°, 30.00°).
///
/// Ported from `kerfcalc.swift/Kits/Materials/MaterialsKit/Sources/MaterialsKit/CompoundMiter.swift`.
public enum Miter {
    private static let d2r = Double.pi / 180, r2d = 180 / Double.pi

    /// Simple flat-frame miter: each of the N joints is cut at 180/N degrees
    /// (two joints per corner sum to 360/N, the exterior angle).
    public static func simpleDeg(sides n: Int) -> Double {
        precondition(n >= 3, "a closed frame has at least 3 sides")
        return 180.0 / Double(n)
    }

    /// The miter for a measured corner that is not square — half the corner angle's supplement.
    /// A 90° corner gives 45°; a 135° corner gives 22.5°.
    public static func forCornerDeg(_ corner: Double) -> Double {
        precondition(corner > 0 && corner < 180, "a corner is between 0 and 180 degrees")
        return (180 - corner) / 2
    }

    /// Compound saw settings for sloped/crown work.
    ///
    /// `springDeg` is the spring angle measured from the wall (vertical) — 38° and 45° are the
    /// common crown springs. `sides` gives the corner: a square inside corner is a 4-sided frame.
    ///   miter = atan( sin(spring) · tan(180/N) )
    ///   bevel = asin( cos(spring) · cos(180/N) )
    public static func compound(springDeg spring: Double, sides n: Int) -> (miter: Double, bevel: Double) {
        precondition(n >= 3, "a closed frame has at least 3 sides")
        let half = (180.0 / Double(n)) * d2r
        let s = spring * d2r
        return (atan(sin(s) * tan(half)) * r2d, asin(cos(s) * cos(half)) * r2d)
    }
}
