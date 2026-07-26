import Foundation

/// Miter and compound (crown) angle math. Pure, stateless.
/// BORROWED VERBATIM from `calculators/kerf.swift` KerfKit.Angles — already oracle-tested against
/// published crown-molding tables; citation preserved below.
public enum CompoundMiter {
    private static let d2r = Double.pi / 180, r2d = 180 / Double.pi

    /// Simple flat-frame miter: each of the N joints is cut at 180/N degrees
    /// (two joints per corner sum to 360/N, the exterior angle).
    public static func simpleMiterDeg(sides n: Int) -> Double { 180.0 / Double(n) }

    /// Compound saw settings for sloped/crown work.
    ///
    /// `springDeg` is the spring angle measured from the wall (vertical) — 38° and 45° are the
    /// common crown springs. `sides` gives the corner: a square inside corner is a 4-sided frame.
    ///   miter = atan( sin(spring) · tan(180/N) )
    ///   bevel = asin( cos(spring) · cos(180/N) )
    /// Matches published crown tables: 38°→(31.62°, 33.86°), 45°→(35.26°, 30.00°).
    public static func compound(springDeg spring: Double, sides n: Int) -> (miter: Double, bevel: Double) {
        let half = (180.0 / Double(n)) * d2r
        let s = spring * d2r
        let miter = atan(sin(s) * tan(half)) * r2d
        let bevel = asin(cos(s) * cos(half)) * r2d
        return (miter, bevel)
    }
}
