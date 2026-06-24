import Foundation

/// The ten classical chart bodies, in the demo's display order.
public enum CelestialBody: String, CaseIterable, Identifiable, Hashable {
    case sun, moon, mercury, venus, mars, jupiter, saturn, uranus, neptune, pluto

    public var id: String { rawValue }

    public var name: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    public var glyph: String {
        switch self {
        case .sun: "☉"; case .moon: "☽"; case .mercury: "☿"; case .venus: "♀"
        case .mars: "♂"; case .jupiter: "♃"; case .saturn: "♄"; case .uranus: "♅"
        case .neptune: "♆"; case .pluto: "♇"
        }
    }

    /// Inner planets that can pass between Earth and Sun (have inferior conjunctions).
    public var isInferior: Bool { self == .mercury || self == .venus }

    /// Planets beyond Earth's orbit (have oppositions instead of inferior conjunctions).
    public var isSuperior: Bool { !isInferior && self != .sun && self != .moon }
}

/// The twelve tropical zodiac signs.
public enum ZodiacSign: Int, CaseIterable {
    case aries, taurus, gemini, cancer, leo, virgo
    case libra, scorpio, sagittarius, capricorn, aquarius, pisces

    public var name: String {
        ["Aries", "Taurus", "Gemini", "Cancer", "Leo", "Virgo",
         "Libra", "Scorpio", "Sagittarius", "Capricorn", "Aquarius", "Pisces"][rawValue]
    }

    public var glyph: String {
        ["♈", "♉", "♊", "♋", "♌", "♍", "♎", "♏", "♐", "♑", "♒", "♓"][rawValue]
    }

    /// Sign containing the given ecliptic longitude.
    public static func from(longitude: Double) -> ZodiacSign {
        ZodiacSign(rawValue: Int(AstroMath.norm360(longitude) / 30) % 12)!
    }
}
