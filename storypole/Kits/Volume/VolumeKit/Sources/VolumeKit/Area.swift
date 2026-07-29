import Foundation

/// Plane-area math for takeoffs. Pure, stateless.
/// Units are whatever the caller supplies (keep them consistent); results are in those units squared.
///
/// Oracle class: IDENTITY — closed-form geometry, cross-checked numerically.
/// Ported from `kerfcalc.swift/Kits/Geometry/GeometryKit/Sources/GeometryKit/Area.swift`
/// and re-gated in `AreaVolumeTests`.
public enum Area {
    public static func rectangle(length l: Double, width w: Double) -> Double { l * w }

    public static func triangle(base b: Double, height h: Double) -> Double { 0.5 * b * h }

    /// Triangle area from three side lengths (Heron's formula).
    /// Returns 0 for a side set that cannot close a triangle, rather than NaN.
    public static func triangle(a: Double, b: Double, c: Double) -> Double {
        let s = (a + b + c) / 2
        let v = s * (s - a) * (s - b) * (s - c)
        return v > 0 ? v.squareRoot() : 0
    }

    public static func trapezoid(base1 a: Double, base2 b: Double, height h: Double) -> Double {
        (a + b) / 2 * h
    }

    /// Area of a rectangle given in feet and inches, returned in square feet — the square-footage
    /// case the incumbent cannot do at all (defect ③).
    public static func squareFeet(lengthIn: Double, widthIn: Double) -> Double {
        lengthIn * widthIn / 144
    }
}
