import Foundation

/// Degree-based trig + angle helpers. The whole engine works in degrees
/// (matching the demo and the classical orbital-element formulae).
public enum AstroMath {
    static let deg = 180.0 / Double.pi
    static let rad = Double.pi / 180.0

    static func sind(_ x: Double) -> Double { sin(x * rad) }
    static func cosd(_ x: Double) -> Double { cos(x * rad) }
    static func tand(_ x: Double) -> Double { tan(x * rad) }
    static func asind(_ x: Double) -> Double { asin(x) * deg }
    static func atan2d(_ y: Double, _ x: Double) -> Double { atan2(y, x) * deg }

    /// Normalize to [0, 360).
    public static func norm360(_ a: Double) -> Double {
        let m = a.truncatingRemainder(dividingBy: 360)
        return m < 0 ? m + 360 : m
    }

    /// Normalize to (-180, 180].
    public static func norm180(_ a: Double) -> Double {
        var d = norm360(a)
        if d > 180 { d -= 360 }
        return d
    }

    /// Unsigned angular separation in [0, 180].
    public static func separation(_ a: Double, _ b: Double) -> Double {
        abs(norm180(a - b))
    }
}
