import Foundation

/// Absolute roughness of a duct's inside surface.
///
/// ## Categories, not brand names
///
/// These are the **published roughness categories** — smooth through rough — rather than a list of
/// products, because that is the form the source data takes and because a category is honest about
/// its own precision. "Flexible duct" spans 1.0 to 4.6 mm depending on how well it is stretched;
/// pretending a single number belongs to a product name would be inventing precision that the
/// published data does not have.
///
/// ## Source
///
/// ASHRAE Fundamentals, duct design chapter, duct roughness factors. The example materials on each
/// case are the published ones.
///
/// ## Why this is not decoration
///
/// Roughness changes the answer. At 1,000 CFM and 0.1 in w.g./100 ft the required diameter runs
/// from 13.4 in for smooth duct to 16.5 in for rough flex — three inches of difference, and the
/// difference between a system that works and one that starves. The design scaffold this app grew
/// from listed four materials and then never used the value, so the picker moved and nothing
/// happened; ``DuctKitTests/RoughnessTests/everyRoughnessGivesADifferentAnswer()`` exists to make
/// sure that cannot come back.
public enum DuctRoughness: String, CaseIterable, Sendable, Codable, Hashable, Identifiable {

    /// 0.03 mm — PVC, aluminium, drawn tubing.
    case smooth
    /// 0.09 mm — galvanized steel, longitudinal or spiral seam; rigid fibrous glass board.
    /// The default: it is what most sheet-metal duct is.
    case mediumSmooth
    /// 0.15 mm — fibrous glass duct liner, air side with facing.
    case average
    /// 0.9 mm — fibrous glass duct liner, air side spray-coated.
    case mediumRough
    /// 3.0 mm — flexible duct, fabric and wire, fully extended.
    case rough

    public var id: String { rawValue }

    /// Absolute roughness ε, metres.
    public var absoluteRoughness: Double {
        switch self {
        case .smooth:       return 0.03e-3
        case .mediumSmooth: return 0.09e-3
        case .average:      return 0.15e-3
        case .mediumRough:  return 0.9e-3
        case .rough:        return 3.0e-3
        }
    }

    /// The published example materials for this category.
    public var examples: [String] {
        switch self {
        case .smooth:       return ["PVC", "aluminium", "drawn tubing"]
        case .mediumSmooth: return ["galvanized steel", "spiral seam steel", "rigid fibrous glass"]
        case .average:      return ["fibrous glass liner, faced"]
        case .mediumRough:  return ["fibrous glass liner, spray-coated"]
        case .rough:        return ["flexible duct, fully extended"]
        }
    }

    /// What most sheet-metal duct is, and the roughness the published friction chart is drawn for.
    public static let `default` = DuctRoughness.mediumSmooth
}

/// The air actually in the duct.
///
/// Friction depends on density and viscosity, and density is where altitude enters. Defaulting
/// this to standard air is offered as a convenience, but the app passes the density of the solved
/// air state so that a duct sized in Denver is sized for Denver's air.
public struct AirProperties: Equatable, Sendable, Codable, Hashable {
    /// kg/m³.
    public let density: Double
    /// Dynamic viscosity, Pa·s.
    public let dynamicViscosity: Double

    public init(density: Double, dynamicViscosity: Double = AirProperties.standardViscosity) {
        self.density = density
        self.dynamicViscosity = dynamicViscosity
    }

    /// Dynamic viscosity of air at 20 °C, Pa·s — the value the published friction chart is drawn
    /// with. Viscosity varies only weakly over the temperature range a duct sees, so it is a
    /// constant here rather than a fourth input nobody has.
    public static let standardViscosity = 1.825e-5

    /// "Standard air": 1.2015 kg/m³, the 0.075 lb/ft³ the trade's constants assume.
    public static let standard = AirProperties(density: 1.2014693)
}
