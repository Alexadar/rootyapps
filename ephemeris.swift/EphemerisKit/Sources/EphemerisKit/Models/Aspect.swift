import Foundation

/// One of the five Ptolemaic aspect types (angle + base orb). Pure data — UI color
/// lives in the app layer as an extension keyed by `name`.
public struct AspectType: Identifiable, Hashable {
    public let name: String
    public let angle: Double
    public let baseOrb: Double
    public let glyph: String

    public var id: String { name }

    public init(name: String, angle: Double, baseOrb: Double, glyph: String) {
        self.name = name; self.angle = angle; self.baseOrb = baseOrb; self.glyph = glyph
    }

    public static let all: [AspectType] = [
        AspectType(name: "Conjunction", angle: 0,   baseOrb: 8, glyph: "☌"),
        AspectType(name: "Sextile",     angle: 60,  baseOrb: 4, glyph: "⚹"),
        AspectType(name: "Square",      angle: 90,  baseOrb: 6, glyph: "□"),
        AspectType(name: "Trine",       angle: 120, baseOrb: 6, glyph: "△"),
        AspectType(name: "Opposition",  angle: 180, baseOrb: 8, glyph: "☍"),
    ]
}

/// A computed planet position for a moment.
public struct BodyPosition: Identifiable, Hashable {
    public let body: CelestialBody
    public let longitude: Double   // ecliptic, degrees [0,360)
    public let speed: Double       // degrees/day; negative = retrograde

    public init(body: CelestialBody, longitude: Double, speed: Double) {
        self.body = body; self.longitude = longitude; self.speed = speed
    }

    public var id: CelestialBody { body }
    public var sign: ZodiacSign { ZodiacSign.from(longitude: longitude) }
    public var degreesInSign: Double { AstroMath.norm360(longitude).truncatingRemainder(dividingBy: 30) }
    public var retrograde: Bool { speed < 0 }

    /// "d° mm′" within the sign.
    public var degMinString: String {
        let dd = Int(degreesInSign)
        let mm = Int((degreesInSign - Double(dd)) * 60 + 0.5)
        return "\(dd)° \(String(format: "%02d", mm))′"
    }
}

/// A detected aspect between two bodies.
public struct DetectedAspect: Identifiable, Hashable {
    public let type: AspectType
    public let a: CelestialBody
    public let b: CelestialBody
    public let orb: Double

    public init(type: AspectType, a: CelestialBody, b: CelestialBody, orb: Double) {
        self.type = type; self.a = a; self.b = b; self.orb = orb
    }

    public var id: String { "\(a.rawValue)-\(type.name)-\(b.rawValue)" }
}

/// Aspect detection — the demo's tightest-match double loop, made testable.
public enum Aspects {
    public static func detect(in positions: [BodyPosition], orbFactor: Double) -> [DetectedAspect] {
        var found: [DetectedAspect] = []
        for i in 0..<positions.count {
            for j in (i + 1)..<positions.count {
                let s = AstroMath.separation(positions[i].longitude, positions[j].longitude)
                for type in AspectType.all where abs(s - type.angle) <= type.baseOrb * orbFactor {
                    found.append(DetectedAspect(type: type, a: positions[i].body,
                                                b: positions[j].body, orb: abs(s - type.angle)))
                    break
                }
            }
        }
        return found.sorted { $0.orb < $1.orb }
    }
}
