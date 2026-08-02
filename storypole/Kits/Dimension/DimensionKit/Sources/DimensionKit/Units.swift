import Foundation

/// Length units and their conversions.
///
/// The inch-pound factors are **exact by definition**, not approximations: the 1959 refixing of
/// the yard and pound made 1 yd ≡ 0.9144 m, hence 1 ft ≡ 0.3048 m and 1 in ≡ 25.4 mm exactly.
/// Federal Register doc 59-5442, 24 FR 5348 (NBS, 30 June 1959), quoted by NIST *SI Units – Length*:
/// *"The value for the inch, derived from the value of the Yard effective July 1, 1959, is exactly
/// equivalent to 25.4 mm."* — https://www.nist.gov/pml/owm/si-units-length
///
/// Pure, stateless.
public enum LengthUnit: String, CaseIterable, Identifiable, Sendable {
    case millimeter, centimeter, meter, inch, foot, yard
    public var id: String { rawValue }

    /// Exact metres in one of this unit, as a rational — so `in → mm → in` round-trips exactly.
    public var metersPerUnit: Rational {
        switch self {
        case .millimeter: return Rational(1, 1000)
        case .centimeter: return Rational(1, 100)
        case .meter:      return Rational(1)
        case .inch:       return Rational(254, 10000)     // 25.4 mm exactly
        case .foot:       return Rational(3048, 10000)    // 12 × 0.0254
        case .yard:       return Rational(9144, 10000)    // 36 × 0.0254
        }
    }

    public var symbol: String {
        switch self {
        case .millimeter: return "mm"
        case .centimeter: return "cm"
        case .meter:      return "m"
        case .inch:       return "in"
        case .foot:       return "ft"
        case .yard:       return "yd"
        }
    }

    /// True for the units a tape is actually marked in.
    public var isImperial: Bool { self == .inch || self == .foot || self == .yard }
}

public enum Units {
    /// Convert exactly between units. Every factor is a defined rational, so this loses nothing.
    public static func convert(_ value: Rational, from: LengthUnit, to: LengthUnit) -> Rational {
        value * from.metersPerUnit / to.metersPerUnit
    }

    /// Double convenience for call sites that already hold a `Double` (UI fields, trig results).
    public static func convert(_ value: Double, from: LengthUnit, to: LengthUnit) -> Double {
        value * from.metersPerUnit.doubleValue / to.metersPerUnit.doubleValue
    }

    // MARK: - US survey foot (legacy)

    /// The **US survey foot**: 1 ft = 1200/3937 m exactly. Deprecated, and offered only as an
    /// explicitly labelled legacy mode for historic survey data.
    ///
    /// 85 FR 62698 (2020-10-05), *"Deprecation of the United States (U.S.) Survey Foot"*:
    /// *"Beginning on January 1, 2023, the U.S. survey foot should not be used."*
    /// https://www.federalregister.gov/documents/2020/10/05/2020-21902/deprecation-of-the-united-states-us-survey-foot
    ///
    /// The app default is `LengthUnit.foot`, the international foot.
    public static let surveyFootMeters = Rational(1200, 3937)

    /// Difference between the two feet over a distance, in international feet. Exactly zero is
    /// impossible: the ratio is 1200/3937 ÷ 381/1250, which is not 1.
    public static func surveyFootDrift(overFeet n: Rational) -> Rational {
        n * (surveyFootMeters / LengthUnit.foot.metersPerUnit) - n
    }

    /// Decimal feet at surveyor's precision — tenths or hundredths of a foot, **not** feet-and-inches.
    public static func inchesToDecimalFeet(_ inches: Double, places: Int = 2) -> Double {
        let f = inches / 12
        let p = pow(10.0, Double(places))
        return (f * p).rounded() / p
    }
}
