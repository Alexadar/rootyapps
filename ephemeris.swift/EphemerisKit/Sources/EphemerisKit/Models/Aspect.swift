import Foundation

/// One of the five Ptolemaic aspect types (angle + base orb). Pure data — UI color
/// lives in the app layer as an extension keyed by `name`.
public struct AspectType: Identifiable, Hashable, Sendable {
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
        // Round to whole arcminutes first, then carry, so 10°60′ becomes 11°00′.
        let totalMinutes = Int((degreesInSign * 60).rounded())
        var dd = totalMinutes / 60
        let mm = totalMinutes % 60
        if dd >= 30 { dd -= 30 }   // keep degrees within the 0–29° sign range
        return "\(dd)° \(String(format: "%02d", mm))′"
    }
}

/// A detected aspect between two bodies.
public struct DetectedAspect: Identifiable, Hashable, Sendable {
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
    /// The aspect a separation belongs to, when more than one is in orb.
    ///
    /// Exactness decides, not declaration order. Where two types both admit a separation, the one it
    /// is *closest to* wins: 78° is 12° from a square and 18° from a sextile, so it is a square. This
    /// is the documented convention — "the aspect closest to exactness receives primary emphasis"
    /// (astro.com AstroWiki; astrolibrary.org) — and no source anywhere ranks aspects by list order.
    ///
    /// This used to `break` on the first type in `AspectType.all` that fit, which contradicted the
    /// "tightest-match" in the comment above and disagreed with `detect(between:and:)`. Two functions
    /// answering the same question differently is the defect class that produced `ChartGeometry`.
    ///
    /// Unreachable from the app either way: overlap needs `orbFactor` ≥ 2.5 (square 90±6f against
    /// trine 120±6f) and the orb slider stops at 1.6. It is reachable through the Kit API, which is
    /// why it is fixed rather than documented as a quirk.
    static func tightest(for separation: Double, orbFactor: Double) -> (type: AspectType, orb: Double)? {
        AspectType.all
            .map { (type: $0, orb: abs(separation - $0.angle)) }
            .filter { $0.orb <= $0.type.baseOrb * orbFactor }
            .min { $0.orb < $1.orb }
    }

    public static func detect(in positions: [BodyPosition], orbFactor: Double) -> [DetectedAspect] {
        var found: [DetectedAspect] = []
        for i in 0..<positions.count {
            for j in (i + 1)..<positions.count {
                let s = AstroMath.separation(positions[i].longitude, positions[j].longitude)
                if let hit = tightest(for: s, orbFactor: orbFactor) {
                    found.append(DetectedAspect(type: hit.type, a: positions[i].body,
                                                b: positions[j].body, orb: hit.orb))
                }
            }
        }
        return found.sorted { $0.orb < $1.orb }
    }
}
