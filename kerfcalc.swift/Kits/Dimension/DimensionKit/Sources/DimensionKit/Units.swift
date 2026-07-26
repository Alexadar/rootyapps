import Foundation

/// Length units and exact conversions. Factors are the NIST/1959-international definitions, not
/// approximations: 1 in ≡ 25.4 mm, 1 ft ≡ 0.3048 m, 1 yd ≡ 0.9144 m.
/// (NIST SP 811, App. B; the international foot — the US survey foot is deprecated after 2023-01-01.)
public enum LengthUnit: String, CaseIterable, Identifiable, Sendable {
    case millimeter, centimeter, meter, inch, foot, yard
    public var id: String { rawValue }

    /// Exact metres in one of this unit.
    public var metersPerUnit: Double {
        switch self {
        case .millimeter: return 0.001
        case .centimeter: return 0.01
        case .meter:      return 1
        case .inch:       return 0.0254      // 25.4 mm exactly
        case .foot:       return 0.3048      // 12 × 0.0254
        case .yard:       return 0.9144      // 36 × 0.0254
        }
    }

    public var symbol: String {
        switch self {
        case .millimeter: return "mm"; case .centimeter: return "cm"; case .meter: return "m"
        case .inch: return "in"; case .foot: return "ft"; case .yard: return "yd"
        }
    }
}

public enum Units {
    /// Convert a length between units using the exact NIST factors.
    public static func convert(_ value: Double, from: LengthUnit, to: LengthUnit) -> Double {
        value * from.metersPerUnit / to.metersPerUnit
    }

    /// The US survey foot (legacy): 1 ft = 1200/3937 m. Offered only for historic survey data;
    /// the app default is the international foot (`LengthUnit.foot`).
    public static let surveyFootMeters = 1200.0 / 3937.0

    /// Decimal feet at "engineer's" precision — tenths or hundredths of a foot (surveying),
    /// NOT feet-and-inches. e.g. 6 in = 0.50 ft.
    public static func inchesToDecimalFeet(_ inches: Double, places: Int = 2) -> Double {
        let f = inches / 12
        let p = pow(10.0, Double(places))
        return (f * p).rounded() / p
    }
}
