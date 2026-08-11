import Foundation

public enum FanError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidInput(name: String, value: Double)
    /// A ratio with a zero denominator — a fan at zero speed has no law to scale from.
    case indeterminate(name: String)

    public var description: String {
        switch self {
        case .invalidInput(let name, let value): return "\(name) is \(value)"
        case .indeterminate(let name): return "\(name) is zero, so nothing can be scaled from it"
        }
    }
}

/// The fan affinity laws, with the density correction that is not optional.
///
/// ## Source
///
/// The affinity relations as published in every fan-engineering reference (and in AMCA's
/// literature): for one fan at fixed diameter,
///
/// * flow varies with speed: `Q₂/Q₁ = N₂/N₁`
/// * pressure varies with the square: `P₂/P₁ = (N₂/N₁)²`
/// * power varies with the cube: `W₂/W₁ = (N₂/N₁)³`
///
/// These are exact algebraic relations, so the oracle for them is algebra — a worked case computed
/// by hand agrees to the last bit, and any tolerance looser than that is hiding a typo.
///
/// ## The density trap
///
/// **Flow does not change with density; pressure and power do.** A fan is a constant-volume
/// machine: move it to Denver and it still shifts the same CFM, but it develops 18 % less static
/// pressure and draws 18 % less power. Two consequences the app must not hide:
///
/// * A fan selected on sea-level curves will not make its design pressure at altitude.
/// * A motor sized on altitude power will be overloaded when the same fan runs at sea level, or
///   on a cold winter start — which is when air is densest.
///
/// Density is therefore a required argument on the pressure and power scalings, never a default.
public enum FanLaws {

    // MARK: - Speed

    /// Flow at a new speed. `Q₂ = Q₁ · N₂/N₁` — independent of density.
    public static func flow(_ flow: Double, fromSpeed n1: Double, toSpeed n2: Double) throws -> Double {
        try validate(flow, "flow")
        return flow * (try speedRatio(n1, n2))
    }

    /// Static pressure at a new speed and density. `P₂ = P₁ · (N₂/N₁)² · (ρ₂/ρ₁)`
    public static func pressure(_ pressure: Double, fromSpeed n1: Double, toSpeed n2: Double,
                                fromDensity d1: Double, toDensity d2: Double) throws -> Double {
        try validate(pressure, "pressure")
        let n = try speedRatio(n1, n2)
        return pressure * n * n * (try densityRatio(d1, d2))
    }

    /// Shaft power at a new speed and density. `W₂ = W₁ · (N₂/N₁)³ · (ρ₂/ρ₁)`
    public static func power(_ power: Double, fromSpeed n1: Double, toSpeed n2: Double,
                             fromDensity d1: Double, toDensity d2: Double) throws -> Double {
        try validate(power, "power")
        let n = try speedRatio(n1, n2)
        return power * n * n * n * (try densityRatio(d1, d2))
    }

    /// The speed needed to reach a target flow. The inverse of ``flow(_:fromSpeed:toSpeed:)``.
    public static func speed(forFlow target: Double, fromFlow flow: Double,
                             atSpeed speed: Double) throws -> Double {
        try validate(target, "target flow")
        try validate(speed, "speed")
        guard flow > 0, flow.isFinite else { throw FanError.indeterminate(name: "flow") }
        return speed * target / flow
    }

    // MARK: - Density alone

    /// Static pressure at a different density, same speed. The altitude correction on its own.
    public static func pressureAtDensity(_ pressure: Double, fromDensity d1: Double,
                                         toDensity d2: Double) throws -> Double {
        try Self.pressure(pressure, fromSpeed: 1, toSpeed: 1, fromDensity: d1, toDensity: d2)
    }

    /// Shaft power at a different density, same speed.
    public static func powerAtDensity(_ power: Double, fromDensity d1: Double,
                                      toDensity d2: Double) throws -> Double {
        try Self.power(power, fromSpeed: 1, toSpeed: 1, fromDensity: d1, toDensity: d2)
    }

    // MARK: - Ratios

    public static func speedRatio(_ n1: Double, _ n2: Double) throws -> Double {
        guard n2.isFinite, n2 >= 0 else { throw FanError.invalidInput(name: "new speed", value: n2) }
        guard n1 > 0, n1.isFinite else { throw FanError.indeterminate(name: "original speed") }
        return n2 / n1
    }

    public static func densityRatio(_ d1: Double, _ d2: Double) throws -> Double {
        guard d2.isFinite, d2 > 0 else { throw FanError.invalidInput(name: "new density", value: d2) }
        guard d1 > 0, d1.isFinite else { throw FanError.indeterminate(name: "original density") }
        return d2 / d1
    }

    private static func validate(_ value: Double, _ name: String) throws {
        guard value.isFinite, value >= 0 else {
            throw FanError.invalidInput(name: name, value: value)
        }
    }
}
