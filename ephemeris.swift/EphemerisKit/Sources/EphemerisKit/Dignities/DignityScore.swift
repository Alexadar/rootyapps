import Foundation

/// One row of the traditional dignity/debility ledger.
public enum DignityKind: String, CaseIterable, Sendable {
    case domicile, exaltation, triplicity, term, face
    case detriment, fall, peregrine

    /// Lilly's fortitude weights, *Christian Astrology* (1647), p. 115: house 5,
    /// exaltation 4, triplicity 3, term 2, face 1; detriment −5, fall −4, peregrine −5.
    /// Kept as data so the score is a sum over the ledger, not a hand-written arithmetic
    /// expression that can drift from the table it claims to implement.
    public var points: Int {
        switch self {
        case .domicile:   return 5
        case .exaltation: return 4
        case .triplicity: return 3
        case .term:       return 2
        case .face:       return 1
        case .detriment:  return -5
        case .fall:       return -4
        case .peregrine:  return -5
        }
    }

    public var isDebility: Bool { points < 0 }

    /// Lilly's own labels, for display without a lookup table in the app layer.
    public var name: String {
        switch self {
        case .domicile:   return "Domicile"
        case .exaltation: return "Exaltation"
        case .triplicity: return "Triplicity"
        case .term:       return "Term"
        case .face:       return "Face"
        case .detriment:  return "Detriment"
        case .fall:       return "Fall"
        case .peregrine:  return "Peregrine"
        }
    }
}

/// A planet's essential dignity ledger at one ecliptic longitude.
///
/// Only the *essential* (sign-position) dignities are here. Accidental dignities — house
/// placement, speed, combustion, mutual reception — depend on chart context this type has
/// none of, and blending the two into one number is how the traditional score gets quietly
/// mis-reported.
public struct DignityScore: Hashable, Sendable {
    public let body: CelestialBody
    public let longitude: Double
    public let sign: ZodiacSign
    public let sect: EssentialDignities.Sect
    /// Every dignity and debility that applies, strongest first.
    public let kinds: [DignityKind]

    public init(body: CelestialBody,
                longitude: Double,
                sign: ZodiacSign,
                sect: EssentialDignities.Sect,
                kinds: [DignityKind]) {
        self.body = body; self.longitude = longitude
        self.sign = sign; self.sect = sect; self.kinds = kinds
    }

    /// Lilly's summed fortitude. Positive = essentially strong, negative = debilitated.
    public var total: Int { kinds.reduce(0) { $0 + $1.points } }

    public func has(_ kind: DignityKind) -> Bool { kinds.contains(kind) }

    public var dignities: [DignityKind] { kinds.filter { !$0.isDebility } }
    public var debilities: [DignityKind] { kinds.filter(\.isDebility) }

    public var isPeregrine: Bool { has(.peregrine) }
}

public extension EssentialDignities {

    /// The essential dignity ledger for a body at an ecliptic longitude.
    /// `nil` for Uranus, Neptune and Pluto — the classical tables assign them nothing, and
    /// a zero score would misread as "measured and neutral" rather than "not in the system".
    static func score(_ body: CelestialBody,
                      longitude: Double,
                      sect: Sect) -> DignityScore? {
        guard isClassical(body) else { return nil }
        let (sign, _) = signAndDegree(longitude)
        var kinds: [DignityKind] = []

        if domicileRuler(of: sign) == body { kinds.append(.domicile) }
        // Exaltation is held throughout the sign; the tabulated degree only marks its peak.
        if exaltation(of: body)?.sign == sign { kinds.append(.exaltation) }
        if triplicityRuler(of: sign, sect: sect) == body { kinds.append(.triplicity) }
        if termRuler(at: longitude) == body { kinds.append(.term) }
        if faceRuler(at: longitude) == body { kinds.append(.face) }

        let debilitated = detrimentRuler(of: sign) == body || fall(of: body)?.sign == sign
        if detrimentRuler(of: sign) == body { kinds.append(.detriment) }
        if fall(of: body)?.sign == sign { kinds.append(.fall) }

        // Lilly defines peregrine as "in a sign where he hath no essentiall dignity"
        // (*Christian Astrology* p. 113). CONVENTION, not table: a planet already scored in
        // detriment or fall is not additionally charged the peregrine −5, because that would
        // double-count the same weakness. `hasNoEssentialDignity` exposes the strict reading
        // for callers who want it.
        if kinds.isEmpty && !debilitated { kinds.append(.peregrine) }

        return DignityScore(body: body, longitude: longitude, sign: sign, sect: sect, kinds: kinds)
    }

    /// Strict Lilly reading of "peregrine": the body holds none of the five dignities at
    /// this longitude, whether or not it is also in detriment or fall.
    static func hasNoEssentialDignity(_ body: CelestialBody,
                                      longitude: Double,
                                      sect: Sect) -> Bool {
        guard let s = score(body, longitude: longitude, sect: sect) else { return false }
        return s.dignities.isEmpty
    }
}

public extension BodyPosition {
    /// Convenience for chart code that already holds positions.
    func dignity(sect: EssentialDignities.Sect) -> DignityScore? {
        EssentialDignities.score(body, longitude: longitude, sect: sect)
    }
}
