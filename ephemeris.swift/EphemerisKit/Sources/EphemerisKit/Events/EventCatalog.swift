import Foundation

/// The exposed numeric dictionary: every possible event combination enumerated once,
/// each assigned a stable integer `code`, with an English `label` and a machine `key`.
/// An external indicator switches/colours/scores on the number; this is the legend.
public enum EventCatalog {

    public struct Entry: Codable, Hashable {
        public let code: Int
        public let key: String
        public let label: String
    }

    /// Planets that take part in stations and mundane (planet↔planet) aspects.
    public static let planets: [CelestialBody] =
        CelestialBody.allCases.filter { $0 != .sun && $0 != .moon }

    /// All bodies that can ingress a sign (the full combination space).
    public static let ingressBodies: [CelestialBody] = CelestialBody.allCases

    // MARK: Exposed dictionary

    public static let entries: [Entry] = build()
    public static let labelsByCode: [Int: String] =
        Dictionary(uniqueKeysWithValues: entries.map { ($0.code, $0.label) })
    public static let codeByKey: [String: Int] =
        Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0.code) })

    // MARK: Canonical key for a concrete event

    public static func key(for e: AstroEvent) -> String {
        switch e.kind {
        case .signIngress:        return "ingress.\(e.bodyA.rawValue).\(signSeg(e.sign))"
        case .newMoon:            return "lunation.new.\(signSeg(e.sign))"
        case .fullMoon:           return "lunation.full.\(signSeg(e.sign))"
        case .stationRetrograde:  return "station.\(e.bodyA.rawValue).retro"
        case .stationDirect:      return "station.\(e.bodyA.rawValue).direct"
        case .inferiorConjunction: return "sun.\(e.bodyA.rawValue).inferiorConjunction"
        case .superiorConjunction: return "sun.\(e.bodyA.rawValue).superiorConjunction"
        case .conjunction:        return "sun.\(e.bodyA.rawValue).conjunction"
        case .opposition:         return "sun.\(e.bodyA.rawValue).opposition"
        case .greatestElongationEast: return "sun.\(e.bodyA.rawValue).elongationEast"
        case .greatestElongationWest: return "sun.\(e.bodyA.rawValue).elongationWest"
        case .mundaneAspect:
            let (lo, hi) = orderedPair(e.bodyA, e.bodyB ?? e.bodyA)
            return "aspect.\(lo.rawValue).\(hi.rawValue).\(e.aspect?.name.lowercased() ?? "?")"
        }
    }

    public static func code(for e: AstroEvent) -> Int { codeByKey[key(for: e)] ?? -1 }

    /// Order an unordered body pair by their canonical (allCases) index.
    public static func orderedPair(_ a: CelestialBody, _ b: CelestialBody) -> (CelestialBody, CelestialBody) {
        let ia = CelestialBody.allCases.firstIndex(of: a)!
        let ib = CelestialBody.allCases.firstIndex(of: b)!
        return ia <= ib ? (a, b) : (b, a)
    }

    // MARK: Enumeration

    private static func signSeg(_ s: ZodiacSign?) -> String { (s?.name ?? "?").lowercased() }

    private static func build() -> [Entry] {
        var rows: [(String, String)] = []   // (key, label)

        // Sign ingresses: every body × every sign.
        for b in ingressBodies {
            for s in ZodiacSign.allCases {
                rows.append(("ingress.\(b.rawValue).\(s.name.lowercased())", "\(b.name) enters \(s.name)"))
            }
        }
        // Lunations: New / Full × sign.
        for s in ZodiacSign.allCases {
            rows.append(("lunation.new.\(s.name.lowercased())", "New Moon in \(s.name)"))
        }
        for s in ZodiacSign.allCases {
            rows.append(("lunation.full.\(s.name.lowercased())", "Full Moon in \(s.name)"))
        }
        // Stations: every planet × {retro, direct}.
        for b in planets {
            rows.append(("station.\(b.rawValue).retro", "\(b.name) stations retrograde"))
            rows.append(("station.\(b.rawValue).direct", "\(b.name) stations direct"))
        }
        // Sun-synodic events.
        for b in planets where b.isInferior {
            rows.append(("sun.\(b.rawValue).inferiorConjunction", "\(b.name) inferior conjunction"))
            rows.append(("sun.\(b.rawValue).superiorConjunction", "\(b.name) superior conjunction"))
            rows.append(("sun.\(b.rawValue).elongationEast", "\(b.name) greatest elongation east"))
            rows.append(("sun.\(b.rawValue).elongationWest", "\(b.name) greatest elongation west"))
        }
        for b in planets where b.isSuperior {
            rows.append(("sun.\(b.rawValue).conjunction", "\(b.name) conjunction Sun"))
            rows.append(("sun.\(b.rawValue).opposition", "\(b.name) opposition Sun"))
        }
        // Mundane planet↔planet aspects: unordered pairs × aspect types.
        for i in 0..<planets.count {
            for j in (i + 1)..<planets.count {
                let lo = planets[i], hi = planets[j]
                for asp in AspectType.all {
                    rows.append(("aspect.\(lo.rawValue).\(hi.rawValue).\(asp.name.lowercased())",
                                 "\(lo.name) \(asp.name.lowercased()) \(hi.name)"))
                }
            }
        }

        return rows.enumerated().map { Entry(code: $0.offset, key: $0.element.0, label: $0.element.1) }
    }
}
