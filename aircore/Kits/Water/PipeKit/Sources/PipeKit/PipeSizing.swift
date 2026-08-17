import Foundation
import FluidKit

public enum PipeError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidInput(name: String, value: Double)
    case noSolution(name: String)

    public var description: String {
        switch self {
        case .invalidInput(let name, let value): return "\(name) is \(value)"
        case .noSolution(let name): return "no pipe size satisfies \(name)"
        }
    }
}

/// Which correlation produced a head loss.
///
/// Both are legitimate and they do not agree — Hazen–Williams runs 2 % to 20 % above Darcy for
/// copper across the small-bore range. Every result carries its method so the app can label it,
/// because a number that is 15 % different depending on an unstated choice is not a number a
/// technician can act on.
public enum HeadLossMethod: String, Sendable, Codable, Hashable, CaseIterable, Identifiable {
    /// Darcy–Weisbach with Colebrook–White. Physics; works for any fluid, temperature and velocity.
    case darcyWeisbach
    /// Hazen–Williams. An empirical fit for water near 15 °C at ordinary velocities — simpler, and
    /// what much of the plumbing literature is written in.
    case hazenWilliams

    public var id: String { rawValue }
}

/// Water pipe sizing: head loss, velocity, and the limits that matter.
///
/// ## Sources
///
/// * **Darcy–Weisbach** with **Colebrook–White**, shared with the duct side in ``FluidKit``.
/// * **Hazen–Williams**, SI form `h_f/L = 10.67 Q^1.852 / (C^1.852 D^4.8704)`, head in metres of
///   water per metre of pipe, Q in m³/s, D in m.
/// * Velocity limits: the published copper-tube erosion figures — 2.4 m/s (8 ft/s) for cold water
///   in continuous service, 1.5 m/s (5 ft/s) hot — and the 0.6 m/s (2 ft/s) minimum conventionally
///   used to keep air entrained. All three are editable defaults, not embedded code limits.
public enum PipeSizing {

    /// Standard gravity, m/s² — head in metres and pressure in pascals are the same statement
    /// through `Δp = ρ g h`.
    public static let standardGravity = 9.80665

    /// Bore sizes this Kit will search, metres: 3 mm to 3 m.
    public static let diameterSearchRange = 0.003 ... 3.0

    // MARK: - Velocity

    /// Mean velocity, m/s.
    public static func velocity(flow q: Double, innerDiameter d: Double) throws -> Double {
        try mapping { try FluidFriction.velocity(volumeFlow: q, diameter: d) }
    }

    /// Bore that carries a flow at a velocity, m.
    public static func innerDiameter(flow q: Double, velocity v: Double) throws -> Double {
        try mapping { try FluidFriction.diameter(volumeFlow: q, velocity: v) }
    }

    public static func reynoldsNumber(velocity v: Double, innerDiameter d: Double,
                                      water: WaterProperties = .standard) throws -> Double {
        try mapping {
            try FluidFriction.reynoldsNumber(velocity: v, diameter: d, fluid: water.fluid)
        }
    }

    // MARK: - Head loss

    /// Head loss per metre of straight pipe, metres of water per metre — Darcy–Weisbach.
    public static func headLossGradient(flow q: Double, innerDiameter d: Double,
                                        material: PipeMaterial = .copper,
                                        water: WaterProperties = .standard) throws -> Double {
        try headLossGradient(flow: q, innerDiameter: d,
                             absoluteRoughness: material.absoluteRoughness, water: water)
    }

    /// Darcy–Weisbach head loss gradient for an explicit roughness, m/m.
    public static func headLossGradient(flow q: Double, innerDiameter d: Double,
                                        absoluteRoughness eps: Double,
                                        water: WaterProperties = .standard) throws -> Double {
        let pressure = try mapping {
            try FluidFriction.pressureGradient(volumeFlow: q, diameter: d,
                                               absoluteRoughness: eps, fluid: water.fluid)
        }
        return pressure / (water.density * standardGravity)
    }

    /// Head loss per metre of straight pipe, metres of water per metre — **Hazen–Williams**.
    ///
    /// Valid for water at ordinary temperatures and velocities. It has no viscosity term, which is
    /// exactly why it is simpler and why it drifts from Darcy on a chilled-water loop.
    public static func hazenWilliamsHeadLossGradient(flow q: Double, innerDiameter d: Double,
                                                     coefficient c: Double) throws -> Double {
        try validate(q, "flow")
        try validate(d, "inner diameter", positive: true)
        try validate(c, "Hazen–Williams coefficient", positive: true)
        guard q > 0 else { return 0 }
        return 10.67 * pow(q, 1.852) / (pow(c, 1.852) * pow(d, 4.8704))
    }

    /// Hazen–Williams from a material's published coefficient.
    public static func hazenWilliamsHeadLossGradient(
        flow q: Double, innerDiameter d: Double, material: PipeMaterial
    ) throws -> Double {
        try hazenWilliamsHeadLossGradient(flow: q, innerDiameter: d,
                                          coefficient: material.hazenWilliamsCoefficient)
    }

    /// Head loss gradient by the named method.
    public static func headLossGradient(flow q: Double, innerDiameter d: Double,
                                        material: PipeMaterial, water: WaterProperties = .standard,
                                        method: HeadLossMethod) throws -> Double {
        switch method {
        case .darcyWeisbach:
            return try headLossGradient(flow: q, innerDiameter: d, material: material, water: water)
        case .hazenWilliams:
            return try hazenWilliamsHeadLossGradient(flow: q, innerDiameter: d, material: material)
        }
    }

    /// Pressure gradient corresponding to a head-loss gradient, Pa/m.
    public static func pressureGradient(headLossGradient h: Double,
                                        water: WaterProperties = .standard) throws -> Double {
        try validate(h, "head loss gradient")
        return h * water.density * standardGravity
    }

    // MARK: - Sizing

    /// Bore that carries a flow at a target head-loss gradient, metres (Darcy–Weisbach).
    public static func innerDiameter(flow q: Double, headLossGradient target: Double,
                                     material: PipeMaterial = .copper,
                                     water: WaterProperties = .standard) throws -> Double {
        try validate(q, "flow", positive: true)
        try validate(target, "head loss gradient", positive: true)
        do {
            return try FluidFriction.diameter(
                volumeFlow: q,
                pressureGradient: target * water.density * standardGravity,
                absoluteRoughness: material.absoluteRoughness,
                fluid: water.fluid,
                searchRange: diameterSearchRange)
        } catch FluidError.noSolution {
            throw PipeError.noSolution(name: "this flow at this head loss")
        }
    }

    // MARK: - Velocity limits

    /// A velocity window a run should sit inside, m/s.
    ///
    /// > Note: These are **published rules of thumb the user can change**, not code limits.
    public struct VelocityLimits: Equatable, Sendable, Codable, Hashable {
        public let minimum: Double
        public let maximum: Double

        public init(minimum: Double, maximum: Double) {
            self.minimum = minimum
            self.maximum = maximum
        }

        /// 0.6–2.4 m/s (2–8 ft/s): the conventional minimum for entraining air, and the published
        /// copper erosion limit for cold water in continuous service.
        public static let coldWater = VelocityLimits(minimum: 2 * 0.3048, maximum: 8 * 0.3048)
        /// 0.6–1.5 m/s (2–5 ft/s): hot water erodes copper at a lower velocity.
        public static let hotWater = VelocityLimits(minimum: 2 * 0.3048, maximum: 5 * 0.3048)
    }

    /// Where a velocity sits against its limits.
    public enum VelocityStatus: String, Sendable, Equatable, Hashable {
        /// Below the minimum: air will not be carried out of the run.
        case tooSlow
        case inRange
        /// Above the erosion limit: noise now, thinning pipe wall later.
        case tooFast
    }

    public static func status(velocity v: Double, limits: VelocityLimits) -> VelocityStatus {
        if v < limits.minimum { return .tooSlow }
        if v > limits.maximum { return .tooFast }
        return .inRange
    }

    // MARK: -

    private static func validate(_ value: Double, _ name: String, positive: Bool = false) throws {
        guard value.isFinite, positive ? value > 0 : value >= 0 else {
            throw PipeError.invalidInput(name: name, value: value)
        }
    }

    private static func mapping<T>(_ work: () throws -> T) throws -> T {
        do {
            return try work()
        } catch let error as FluidError {
            switch error {
            case .invalidInput(let name, let value):
                throw PipeError.invalidInput(name: name == "diameter" ? "inner diameter" : name,
                                             value: value)
            case .noSolution(let name):
                throw PipeError.noSolution(name: name)
            }
        }
    }
}
