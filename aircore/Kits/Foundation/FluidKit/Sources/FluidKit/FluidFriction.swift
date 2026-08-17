import Foundation

public enum FluidError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidInput(name: String, value: Double)
    case noSolution(name: String)

    public var description: String {
        switch self {
        case .invalidInput(let name, let value): return "\(name) is \(value)"
        case .noSolution(let name): return "no solution for \(name)"
        }
    }
}

/// Pipe-and-duct friction: the part that is the same fluid whether it is air or water.
///
/// ## Why this is a Kit of its own
///
/// The other Kits in this app are deliberately independent of one another — each takes SI
/// primitives and owns its whole domain. This one is the exception, and it is a considered one.
/// DuctKit and PipeKit both need Colebrook–White and Darcy–Weisbach, and they are *the same
/// equations*: air in a duct and water in a pipe differ in their density and viscosity, not in
/// their physics. Two copies of an implicit numerical solve would drift — one gets a convergence
/// fix, the other does not — and this repository already has a written-down scar from exactly that
/// (three renderers, three private font helpers, one bug shipped three times).
///
/// So: one implementation, two callers, and the caller supplies the fluid.
///
/// ## Source
///
/// * **Darcy–Weisbach**: `Δp/L = f · ρV² / 2D`
/// * **Colebrook–White**: `1/√f = −2 log₁₀(ε/3.7D + 2.51/Re√f)`, turbulent
/// * **Hagen–Poiseuille**: `f = 64/Re`, laminar
public enum FluidFriction {

    /// Reynolds number below which flow is laminar.
    public static let laminarLimit = 2300.0

    /// A fluid, as friction sees it.
    public struct Fluid: Equatable, Sendable, Codable, Hashable {
        /// kg/m³.
        public let density: Double
        /// Dynamic viscosity, Pa·s.
        public let dynamicViscosity: Double

        public init(density: Double, dynamicViscosity: Double) {
            self.density = density
            self.dynamicViscosity = dynamicViscosity
        }

        /// Kinematic viscosity, m²/s.
        public var kinematicViscosity: Double { dynamicViscosity / density }
    }

    // MARK: - Geometry

    /// Cross-sectional area of a circular section, m².
    public static func circularArea(diameter d: Double) throws -> Double {
        try validate(d, "diameter", positive: true)
        return .pi * d * d / 4
    }

    /// Mean velocity, m/s.
    public static func velocity(volumeFlow q: Double, diameter d: Double) throws -> Double {
        try validate(q, "flow")
        return q / (try circularArea(diameter: d))
    }

    /// Diameter that carries a flow at a velocity, m.
    public static func diameter(volumeFlow q: Double, velocity v: Double) throws -> Double {
        try validate(q, "flow")
        try validate(v, "velocity", positive: true)
        return (4 * q / (.pi * v)).squareRoot()
    }

    // MARK: - Friction

    public static func reynoldsNumber(velocity v: Double, diameter d: Double,
                                      fluid: Fluid) throws -> Double {
        try validate(v, "velocity")
        try validate(d, "diameter", positive: true)
        try validate(fluid.density, "density", positive: true)
        try validate(fluid.dynamicViscosity, "viscosity", positive: true)
        return fluid.density * v * d / fluid.dynamicViscosity
    }

    /// Darcy friction factor.
    ///
    /// Colebrook is implicit in `f`, so it is solved by fixed-point iteration on `1/√f`, seeded
    /// with the Swamee–Jain explicit approximation. The iteration is a contraction across the
    /// turbulent range and settles in a handful of steps; the loop bound is a backstop, not the
    /// convergence strategy.
    ///
    /// Between Re 2,300 and 4,000 the flow is transitional and no correlation is really valid.
    /// Colebrook is continued through that band because a discontinuity there would be worse than
    /// an approximation — but a number computed in it is an estimate, and the caller should say so.
    public static func darcyFrictionFactor(reynoldsNumber re: Double,
                                           relativeRoughness rr: Double) throws -> Double {
        try validate(re, "Reynolds number", positive: true)
        guard rr.isFinite, rr >= 0 else {
            throw FluidError.invalidInput(name: "relative roughness", value: rr)
        }
        if re < laminarLimit { return 64 / re }

        var inverseRoot = -2 * log10(rr / 3.7 + 5.74 / pow(re, 0.9))
        for _ in 0..<64 {
            let next = -2 * log10(rr / 3.7 + 2.51 * inverseRoot / re)
            if abs(next - inverseRoot) < 1e-13 { inverseRoot = next; break }
            inverseRoot = next
        }
        guard inverseRoot > 0 else { throw FluidError.noSolution(name: "friction factor") }
        return 1 / (inverseRoot * inverseRoot)
    }

    /// Is this Reynolds number in the transitional band, where any answer is an estimate?
    public static func isTransitional(reynoldsNumber re: Double) -> Bool {
        re >= laminarLimit && re < 4000
    }

    /// Pressure gradient from Darcy–Weisbach, Pa per metre of straight run.
    public static func pressureGradient(volumeFlow q: Double, diameter d: Double,
                                        absoluteRoughness eps: Double,
                                        fluid: Fluid) throws -> Double {
        let v = try velocity(volumeFlow: q, diameter: d)
        guard v > 0 else { return 0 }
        let re = try reynoldsNumber(velocity: v, diameter: d, fluid: fluid)
        let f = try darcyFrictionFactor(reynoldsNumber: re, relativeRoughness: eps / d)
        return f * fluid.density * v * v / (2 * d)
    }

    /// Diameter that carries a flow at a target pressure gradient, metres.
    ///
    /// The gradient falls monotonically with diameter at fixed flow, so this is a bisection with
    /// no local minima to fall into.
    public static func diameter(volumeFlow q: Double, pressureGradient target: Double,
                                absoluteRoughness eps: Double, fluid: Fluid,
                                searchRange: ClosedRange<Double> = 0.001 ... 5.0) throws -> Double {
        try validate(q, "flow", positive: true)
        try validate(target, "pressure gradient", positive: true)

        var lo = searchRange.lowerBound
        var hi = searchRange.upperBound
        guard try pressureGradient(volumeFlow: q, diameter: lo,
                                   absoluteRoughness: eps, fluid: fluid) > target,
              try pressureGradient(volumeFlow: q, diameter: hi,
                                   absoluteRoughness: eps, fluid: fluid) < target
        else { throw FluidError.noSolution(name: "this flow at this pressure gradient") }

        for _ in 0..<200 {
            let mid = (lo + hi) / 2
            if mid == lo || mid == hi { break }
            if try pressureGradient(volumeFlow: q, diameter: mid,
                                    absoluteRoughness: eps, fluid: fluid) > target {
                lo = mid
            } else {
                hi = mid
            }
        }
        return (lo + hi) / 2
    }

    // MARK: -

    static func validate(_ value: Double, _ name: String, positive: Bool = false) throws {
        guard value.isFinite, positive ? value > 0 : value >= 0 else {
            throw FluidError.invalidInput(name: name, value: value)
        }
    }
}
