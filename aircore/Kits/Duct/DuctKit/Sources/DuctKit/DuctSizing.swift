import Foundation
import FluidKit

public enum DuctError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidInput(name: String, value: Double)
    /// The requested combination has no solution in the range of duct sizes this Kit will consider.
    case noSolution(name: String)

    public var description: String {
        switch self {
        case .invalidInput(let name, let value): return "\(name) is \(value)"
        case .noSolution(let name): return "no duct size satisfies \(name)"
        }
    }
}

/// Straight-duct sizing from friction, in SI.
///
/// > Important: **This sizes straight duct. It is not a duct *design* tool.** There is no fitting
/// > library, no equivalent length and no total effective length here, and there will not be: the
/// > fitting-loss data is licensed. A run sized here still needs its fittings accounted for by
/// > whoever is designing the system.
///
/// ## Source
///
/// **Darcy–Weisbach** with the friction factor from **Colebrook–White**, both implemented once in
/// ``FluidKit`` and shared with the water-side Kit. This is the physics the published friction
/// chart is drawn from, implemented rather than curve-fitted so that roughness, density and
/// viscosity are real inputs instead of assumptions baked into a constant.
///
/// The curve fit — `Δp = 0.109136 Q^1.9 / D^5.02` in IP units, galvanized duct at standard air —
/// is used in the test suite as an independent cross-check, where the two agree within 2 %.
public enum DuctSizing {

    /// Duct diameters this Kit will search, metres: 10 mm to 5 m spans everything from a lab
    /// exhaust to a tunnel fan.
    public static let diameterSearchRange = 0.01 ... 5.0

    /// Reynolds number below which flow is laminar.
    public static let laminarLimit = FluidFriction.laminarLimit

    /// A common rule-of-thumb velocity ceiling, m/s (1,200 fpm).
    ///
    /// > Note: This is a **starting default the user can change**, not a limit from any code or
    /// > standard. Per-application velocity tables — main duct against branch, supply against
    /// > return, by occupancy — are published in licensed documents, so none is embedded here.
    /// > What the app can honestly do is compute the velocity and compare it to a number the user
    /// > owns.
    public static let defaultVelocityLimit = 1200 * 0.3048 / 60

    // MARK: - Geometry

    /// Cross-sectional area of a round duct, m².
    public static func area(diameter d: Double) throws -> Double {
        try mapping { try FluidFriction.circularArea(diameter: d) }
    }

    /// Velocity, m/s.
    public static func velocity(flow q: Double, diameter d: Double) throws -> Double {
        try mapping { try FluidFriction.velocity(volumeFlow: q, diameter: d) }
    }

    /// Diameter that carries a flow at a velocity, m — sizing by velocity rather than friction.
    public static func diameter(flow q: Double, velocity v: Double) throws -> Double {
        try mapping { try FluidFriction.diameter(volumeFlow: q, velocity: v) }
    }

    // MARK: - Friction

    public static func reynoldsNumber(velocity v: Double, diameter d: Double,
                                      air: AirProperties) throws -> Double {
        try mapping {
            try FluidFriction.reynoldsNumber(velocity: v, diameter: d, fluid: air.fluid)
        }
    }

    /// Darcy friction factor — Colebrook–White in turbulent flow, `64/Re` in laminar.
    public static func frictionFactor(reynoldsNumber re: Double,
                                      relativeRoughness rr: Double) throws -> Double {
        try mapping {
            try FluidFriction.darcyFrictionFactor(reynoldsNumber: re, relativeRoughness: rr)
        }
    }

    /// Friction rate, Pa per metre of straight duct.
    public static func frictionRate(flow q: Double, diameter d: Double,
                                    roughness: DuctRoughness = .default,
                                    air: AirProperties = .standard) throws -> Double {
        try frictionRate(flow: q, diameter: d,
                         absoluteRoughness: roughness.absoluteRoughness, air: air)
    }

    /// Friction rate for an explicit absolute roughness, Pa/m.
    public static func frictionRate(flow q: Double, diameter d: Double,
                                    absoluteRoughness eps: Double,
                                    air: AirProperties = .standard) throws -> Double {
        try mapping {
            try FluidFriction.pressureGradient(volumeFlow: q, diameter: d,
                                               absoluteRoughness: eps, fluid: air.fluid)
        }
    }

    /// Round duct diameter that carries a flow at a target friction rate, metres.
    public static func diameter(flow q: Double, frictionRate target: Double,
                                roughness: DuctRoughness = .default,
                                air: AirProperties = .standard) throws -> Double {
        try diameter(flow: q, frictionRate: target,
                     absoluteRoughness: roughness.absoluteRoughness, air: air)
    }

    /// Diameter for an explicit absolute roughness, metres.
    ///
    /// The inputs are checked here rather than left to ``FluidKit`` so that a failure is phrased
    /// in the words on screen — "friction rate", not "pressure gradient".
    public static func diameter(flow q: Double, frictionRate target: Double,
                                absoluteRoughness eps: Double,
                                air: AirProperties = .standard) throws -> Double {
        try validate(q, "flow", positive: true)
        try validate(target, "friction rate", positive: true)
        do {
            return try FluidFriction.diameter(volumeFlow: q, pressureGradient: target,
                                              absoluteRoughness: eps, fluid: air.fluid,
                                              searchRange: diameterSearchRange)
        } catch FluidError.noSolution {
            throw DuctError.noSolution(name: "this flow at this friction rate")
        }
    }

    // MARK: - Round ⇄ rectangular

    /// Circular equivalent of a rectangular duct — the round duct with the same friction loss at
    /// the same flow. `De = 1.30 (ab)^0.625 / (a+b)^0.25`
    ///
    /// Published in the duct design literature and dimensionally homogeneous, so the sides and the
    /// result may be in any consistent unit.
    public static func equivalentDiameter(width a: Double, height b: Double) throws -> Double {
        try validate(a, "width", positive: true)
        try validate(b, "height", positive: true)
        return 1.30 * pow(a * b, 0.625) / pow(a + b, 0.25)
    }

    /// The other side of a rectangular duct with a given circular equivalent — "I have 200 mm of
    /// ceiling, how wide does it have to be?"
    ///
    /// Inverts the equivalent-diameter equation numerically rather than approximating it. The
    /// scaffold this app grew from returned `0.85 × diameter` here, which satisfies no equation at
    /// all; ``RectangularTests/inverseRoundTripsForEveryAspectRatio()`` holds this to the real
    /// relation.
    public static func rectangularSide(equivalentDiameter de: Double,
                                       knownSide a: Double) throws -> Double {
        try validate(de, "equivalent diameter", positive: true)
        try validate(a, "known side", positive: true)

        var lo = 1e-6
        var hi = 1e3 * de
        guard try equivalentDiameter(width: a, height: lo) < de,
              try equivalentDiameter(width: a, height: hi) > de
        else { throw DuctError.noSolution(name: "a rectangle with that side") }

        for _ in 0..<200 {
            let mid = (lo + hi) / 2
            if mid == lo || mid == hi { break }
            if try equivalentDiameter(width: a, height: mid) < de { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    // MARK: -

    private static func validate(_ value: Double, _ name: String, positive: Bool = false) throws {
        guard value.isFinite, positive ? value > 0 : value >= 0 else {
            throw DuctError.invalidInput(name: name, value: value)
        }
    }

    /// Re-label FluidKit's errors in this Kit's vocabulary, so a caller sees "no duct size
    /// satisfies…" rather than a generic fluid failure it has no context for.
    private static func mapping<T>(_ work: () throws -> T) throws -> T {
        do {
            return try work()
        } catch let error as FluidError {
            switch error {
            case .invalidInput(let name, let value):
                throw DuctError.invalidInput(name: name, value: value)
            case .noSolution(let name):
                throw DuctError.noSolution(name: name)
            }
        }
    }
}

extension AirProperties {
    /// This air, as ``FluidFriction`` sees it.
    var fluid: FluidFriction.Fluid {
        FluidFriction.Fluid(density: density, dynamicViscosity: dynamicViscosity)
    }
}
