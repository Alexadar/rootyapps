import Foundation

/// Circle math — circumference, pipe wrap, arc length, arch segments. Pure, stateless.
///
/// Oracle class: IDENTITY — closed-form geometry.
/// "Pipe wrap" is the practical case: the circumference is the length of the wrap-around template
/// a pipefitter marks a cut with, so it is the same number under a different name.
public enum Circle {
    public static func circumference(radius r: Double) -> Double { 2 * .pi * r }
    public static func circumference(diameter d: Double) -> Double { .pi * d }

    /// The length of material needed to wrap a pipe once — its outside circumference.
    public static func pipeWrap(outsideDiameter d: Double) -> Double { .pi * d }

    public static func area(radius r: Double) -> Double { .pi * r * r }
    public static func area(diameter d: Double) -> Double { .pi * d * d / 4 }

    /// Arc length subtending `angleDeg` at the centre.
    public static func arcLength(radius r: Double, angleDeg: Double) -> Double {
        r * angleDeg * .pi / 180
    }

    /// Area of a circular segment subtending `angleRadians` at the centre. A = ½r²(θ − sin θ).
    public static func segmentArea(radius r: Double, angleRadians t: Double) -> Double {
        0.5 * r * r * (t - sin(t))
    }

    /// Rise (height) of a circular arch of a given span and radius — the arch layout case.
    /// Returns `nil` when the radius is too small to span the opening.
    public static func archRise(span s: Double, radius r: Double) -> Double? {
        let half = s / 2
        guard r >= half else { return nil }
        return r - (r * r - half * half).squareRoot()
    }

    /// The radius of the circle through a chord of `span` with a rise of `rise` —
    /// how a carpenter lays out an arch from the two numbers actually known on site.
    public static func radiusFrom(span s: Double, rise h: Double) -> Double? {
        guard h > 0 else { return nil }
        return (s * s) / (8 * h) + h / 2
    }
}
