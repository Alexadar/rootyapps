import Foundation

/// Plane-area math for takeoffs. Pure, stateless. Units are whatever the caller supplies
/// (keep them consistent); results are in those units squared.
public enum Area {
    public static func rectangle(length l: Double, width w: Double) -> Double { l * w }

    public static func triangle(base b: Double, height h: Double) -> Double { 0.5 * b * h }

    /// Triangle area from three side lengths (Heron's formula).
    public static func triangle(a: Double, b: Double, c: Double) -> Double {
        let s = (a + b + c) / 2
        let v = s * (s - a) * (s - b) * (s - c)
        return v > 0 ? v.squareRoot() : 0
    }

    public static func trapezoid(base1 a: Double, base2 b: Double, height h: Double) -> Double {
        (a + b) / 2 * h
    }

    public static func circle(radius r: Double) -> Double { .pi * r * r }
    public static func circle(diameter d: Double) -> Double { .pi * d * d / 4 }
    public static func circumference(radius r: Double) -> Double { 2 * .pi * r }

    /// Area of a circular segment subtending `angleRadians` at the centre (radius r).
    /// A = ½ r² (θ − sin θ). Used for arches.
    public static func circularSegment(radius r: Double, angleRadians θ: Double) -> Double {
        0.5 * r * r * (θ - sin(θ))
    }
}
