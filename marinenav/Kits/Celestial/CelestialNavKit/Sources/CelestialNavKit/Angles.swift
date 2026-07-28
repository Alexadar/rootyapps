// Ported from calculators/marine-navigation/intercept.swift/InterceptKit (oracle-first harvest, 2026-07-08).
import Foundation

/// Degree-based trig helpers and angle normalisation. Pure, stateless.
enum Deg {
    static func rad(_ d: Double) -> Double { d * .pi / 180 }
    static func deg(_ r: Double) -> Double { r * 180 / .pi }
    static func sin(_ d: Double) -> Double { Foundation.sin(rad(d)) }
    static func cos(_ d: Double) -> Double { Foundation.cos(rad(d)) }
    static func tan(_ d: Double) -> Double { Foundation.tan(rad(d)) }
    static func asin(_ x: Double) -> Double { deg(Foundation.asin(max(-1, min(1, x)))) }
    static func acos(_ x: Double) -> Double { deg(Foundation.acos(max(-1, min(1, x)))) }
    static func atan2(_ y: Double, _ x: Double) -> Double { deg(Foundation.atan2(y, x)) }

    /// Normalise to [0, 360).
    static func norm360(_ a: Double) -> Double {
        let m = a.truncatingRemainder(dividingBy: 360)
        return m < 0 ? m + 360 : m
    }
    /// Normalise to (-180, 180].
    static func norm180(_ a: Double) -> Double {
        var d = norm360(a)
        if d > 180 { d -= 360 }
        return d
    }
}
