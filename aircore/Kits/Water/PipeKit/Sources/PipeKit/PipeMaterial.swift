import Foundation
import FluidKit

/// A pipe material, carrying both roughness constants it is published with.
///
/// ## Two numbers, two methods
///
/// Water-side pressure drop is computed two different ways in the trade, and each wants its own
/// constant: **Darcy–Weisbach** needs an absolute roughness ε, and **Hazen–Williams** needs its own
/// empirical coefficient C. They are not convertible into one another — C absorbs the velocity
/// dependence that Darcy handles explicitly — so both are carried here and the app says which
/// method produced a given number.
///
/// ## Source
///
/// Absolute roughness values are the published pipe-roughness figures used with the Moody chart.
/// Hazen–Williams C values are the published design values; where the literature gives a range for
/// a material, the mid value is used and the range is stated in ``hazenWilliamsRange``.
public enum PipeMaterial: String, CaseIterable, Sendable, Codable, Hashable, Identifiable {

    /// Drawn copper tube — the usual small-bore hydronic material.
    case copper
    /// PVC, CPVC, PEX and other plastics.
    case plastic
    /// New commercial steel.
    case steel
    /// Steel with some age and scale on it.
    case steelAged
    /// Galvanized iron.
    case galvanizedIron
    /// New cast iron.
    case castIron
    /// Old, tuberculated cast iron.
    case castIronOld

    public var id: String { rawValue }

    /// Absolute roughness ε, metres.
    public var absoluteRoughness: Double {
        switch self {
        case .copper:         return 1.5e-6
        case .plastic:        return 1.5e-6
        case .steel:          return 4.5e-5
        case .steelAged:      return 2.0e-4
        case .galvanizedIron: return 1.5e-4
        case .castIron:       return 2.6e-4
        case .castIronOld:    return 1.5e-3
        }
    }

    /// Hazen–Williams roughness coefficient C. Higher is smoother.
    public var hazenWilliamsCoefficient: Double {
        switch self {
        case .copper:         return 140
        case .plastic:        return 150
        case .steel:          return 130
        case .steelAged:      return 100
        case .galvanizedIron: return 120
        case .castIron:       return 130
        case .castIronOld:    return 90
        }
    }

    /// The published range for C, which is wider than a single design value suggests.
    public var hazenWilliamsRange: ClosedRange<Double> {
        switch self {
        case .copper:         return 130 ... 140
        case .plastic:        return 140 ... 150
        case .steel:          return 120 ... 140
        case .steelAged:      return 90 ... 110
        case .galvanizedIron: return 110 ... 120
        case .castIron:       return 120 ... 140
        case .castIronOld:    return 80 ... 100
        }
    }
}

/// Water, as friction sees it.
///
/// Density and viscosity move enough with temperature to matter: a chilled-water loop at 4 °C is
/// 56 % more viscous than the same loop at 20 °C, and that is a real difference in pump head.
/// Values are the published water properties at each temperature.
public struct WaterProperties: Equatable, Sendable, Codable, Hashable {
    /// kg/m³.
    public let density: Double
    /// Dynamic viscosity, Pa·s.
    public let dynamicViscosity: Double

    public init(density: Double, dynamicViscosity: Double) {
        self.density = density
        self.dynamicViscosity = dynamicViscosity
    }

    /// Chilled water, 4 °C.
    public static let chilled = WaterProperties(density: 1000.0, dynamicViscosity: 1.567e-3)
    /// Water at 20 °C — the reference condition, and the default.
    public static let standard = WaterProperties(density: 998.2, dynamicViscosity: 1.002e-3)
    /// Heating water, 60 °C.
    public static let heating = WaterProperties(density: 983.2, dynamicViscosity: 4.665e-4)

    var fluid: FluidFriction.Fluid {
        FluidFriction.Fluid(density: density, dynamicViscosity: dynamicViscosity)
    }
}
