import Foundation

/// Broad classification used for filtering and column tagging.
public enum EventClass: String, CaseIterable, Codable, Hashable {
    case ingress, lunation, station, conjunction, opposition, elongation, aspect
}

/// A single dated astronomical event in the unified timeline. Its `code` and `label`
/// come from `EventCatalog` (the exposed numeric dictionary).
public struct AstroEvent: Hashable {
    public enum Kind: String, CaseIterable, Codable, Hashable {
        case conjunction, inferiorConjunction, superiorConjunction, opposition
        case stationRetrograde, stationDirect
        case greatestElongationEast, greatestElongationWest
        case signIngress, newMoon, fullMoon, mundaneAspect
    }

    public let kind: Kind
    public let date: Date
    public let bodyA: CelestialBody
    public let bodyB: CelestialBody?
    public let aspect: AspectType?
    public let longitudeA: Double
    public let longitudeB: Double?
    public let sign: ZodiacSign?
    public let retroA: Bool
    public let retroB: Bool

    public init(kind: Kind, date: Date, bodyA: CelestialBody, bodyB: CelestialBody? = nil,
                aspect: AspectType? = nil, longitudeA: Double, longitudeB: Double? = nil,
                sign: ZodiacSign? = nil, retroA: Bool = false, retroB: Bool = false) {
        self.kind = kind; self.date = date; self.bodyA = bodyA; self.bodyB = bodyB
        self.aspect = aspect; self.longitudeA = longitudeA; self.longitudeB = longitudeB
        self.sign = sign; self.retroA = retroA; self.retroB = retroB
    }

    public var eventClass: EventClass {
        switch kind {
        case .signIngress: .ingress
        case .newMoon, .fullMoon: .lunation
        case .stationRetrograde, .stationDirect: .station
        case .conjunction, .inferiorConjunction, .superiorConjunction: .conjunction
        case .opposition: .opposition
        case .greatestElongationEast, .greatestElongationWest: .elongation
        case .mundaneAspect: .aspect
        }
    }

    public var glyph: String {
        switch kind {
        case .signIngress: sign?.glyph ?? "↗"
        case .newMoon: "🌑"
        case .fullMoon: "🌕"
        case .stationRetrograde: "℞"
        case .stationDirect: "D"
        case .conjunction, .inferiorConjunction, .superiorConjunction: "☌"
        case .opposition: "☍"
        case .greatestElongationEast: "E"
        case .greatestElongationWest: "W"
        case .mundaneAspect: aspect?.glyph ?? "✦"
        }
    }

    /// Stable machine key for this event's combination (resolves to a catalog code).
    public var key: String { EventCatalog.key(for: self) }

    /// The catalog's numeric code for this combination (−1 if unexpectedly absent).
    public var code: Int { EventCatalog.codeByKey[key] ?? -1 }

    /// English legend text for this event's code.
    public func label() -> String { EventCatalog.labelsByCode[code] ?? key }
}
