import Foundation

/// Traditional essential dignities and debilities: domicile, exaltation, triplicity,
/// term (bound) and face (decan), plus detriment and fall.
///
/// WHY tables, not formulae: these are historical *assignments*, not derivations. Nothing
/// here may be recalled loosely or interpolated — every entry is transcribed from a printed
/// authority (cited per table) and pinned by an external oracle in the test corpus.
///
/// WHY only seven bodies: the scheme predates the outer planets and assigns them nothing.
/// Lookups that answer "which planet" therefore return one of the seven classical bodies,
/// and per-body lookups return `nil` for Uranus/Neptune/Pluto. Filling that hole with modern
/// rulerships would silently blend two incompatible systems inside one score.
///
/// WHY nested types: every name in here (`Sect`, `Element`, `Bound`) is a word other modules
/// in this Kit may want for their own purposes. Nesting keeps the global namespace clean.
public enum EssentialDignities {

    // MARK: - Supporting types

    /// Diurnal or nocturnal chart. Triplicity is the one essential dignity that depends on
    /// it, so it is an explicit argument: this layer has no chart context to infer it from.
    public enum Sect: String, CaseIterable, Sendable {
        case day, night
    }

    /// The four triplicities (elements). Sign order makes this a pure function of the sign
    /// index, so it needs no table.
    public enum Element: String, CaseIterable, Sendable {
        case fire, earth, air, water
    }

    /// One term (bound) or face: a contiguous arc *within a sign*, in degrees from the sign
    /// cusp. Half-open [start, end) so the 360 boundaries partition the zodiac exactly once.
    public struct Bound: Hashable, Sendable {
        public let ruler: CelestialBody
        public let sign: ZodiacSign
        /// Degrees from the sign cusp, 0…30.
        public let start: Double
        public let end: Double

        public init(ruler: CelestialBody, sign: ZodiacSign, start: Double, end: Double) {
            self.ruler = ruler; self.sign = sign; self.start = start; self.end = end
        }

        /// Absolute ecliptic longitude of the bound's start, degrees [0, 360).
        public var startLongitude: Double { Double(sign.rawValue) * 30 + start }
        public var span: Double { end - start }
    }

    /// The seven bodies the classical scheme knows about.
    public static let classicalBodies: [CelestialBody] =
        [.sun, .moon, .mercury, .venus, .mars, .jupiter, .saturn]

    public static func isClassical(_ body: CelestialBody) -> Bool {
        classicalBodies.contains(body)
    }

    // MARK: - Sign helpers

    /// Element of a sign — Aries fire, Taurus earth, Gemini air, Cancer water, repeating.
    public static func element(of sign: ZodiacSign) -> Element {
        Element.allCases[sign.rawValue % 4]
    }

    /// The sign 180° away. Detriment and fall are both defined by opposition, so this is the
    /// only place the 6-sign step is written down.
    public static func opposite(_ sign: ZodiacSign) -> ZodiacSign {
        ZodiacSign(rawValue: (sign.rawValue + 6) % 12)!
    }

    /// Sign and degrees-into-sign for an ecliptic longitude, wrap-safe for any input.
    ///
    /// WHY the degree is derived from the *unwrapped* sign index rather than from
    /// `sign.rawValue`: `norm360` can return exactly 360.0 for a tiny negative input, which
    /// wraps the index back to Aries. Subtracting 12×30 (not 0×30) keeps the degree at 0
    /// instead of 360 and stops the 0/360 seam from walking off the end of the term table —
    /// the failure mode this codebase already paid for once in ChartGeometry.
    public static func signAndDegree(_ longitude: Double) -> (sign: ZodiacSign, degree: Double) {
        let l = AstroMath.norm360(longitude)
        let index = Int(l / 30)
        let sign = ZodiacSign(rawValue: index % 12)!
        let d = l - Double(index) * 30
        return (sign, min(max(d, 0), (30 as Double).nextDown))
    }

    // MARK: - Domicile / detriment
    // Source: William Lilly, *Christian Astrology* (1647), "A Table of the Essential
    // Dignities of the Planets", p. 104. Identical in Ptolemy, *Tetrabiblos* I.17.

    private static let domicileTable: [CelestialBody] = [
        .mars,      // Aries
        .venus,     // Taurus
        .mercury,   // Gemini
        .moon,      // Cancer
        .sun,       // Leo
        .mercury,   // Virgo
        .venus,     // Libra
        .mars,      // Scorpio
        .jupiter,   // Sagittarius
        .saturn,    // Capricorn
        .saturn,    // Aquarius
        .jupiter,   // Pisces
    ]

    /// Domicile (house) ruler of a sign.
    public static func domicileRuler(of sign: ZodiacSign) -> CelestialBody {
        domicileTable[sign.rawValue]
    }

    /// Signs a body rules by domicile. Empty for the outer planets.
    public static func domiciles(of body: CelestialBody) -> [ZodiacSign] {
        ZodiacSign.allCases.filter { domicileRuler(of: $0) == body }
    }

    /// A planet is in detriment in the sign opposite its own — so the detriment "ruler" of a
    /// sign is the domicile ruler of its opposite.
    public static func detrimentRuler(of sign: ZodiacSign) -> CelestialBody {
        domicileRuler(of: opposite(sign))
    }

    public static func detriments(of body: CelestialBody) -> [ZodiacSign] {
        domiciles(of: body).map(opposite)
    }

    // MARK: - Exaltation / fall
    // Source: Lilly, *Christian Astrology* (1647), p. 104 (exaltation column, with degrees);
    // Ptolemy, *Tetrabiblos* I.19. The lunar-node exaltation (Gemini 3) is omitted: this Kit
    // has no node body.

    private static let exaltationTable: [CelestialBody: (sign: ZodiacSign, degree: Double)] = [
        .sun:     (.aries, 19),
        .moon:    (.taurus, 3),
        .mercury: (.virgo, 15),
        .venus:   (.pisces, 27),
        .mars:    (.capricorn, 28),
        .jupiter: (.cancer, 15),
        .saturn:  (.libra, 21),
    ]

    /// Sign of exaltation and the degree of greatest exaltation. `nil` for outer planets.
    ///
    /// The *degree* marks where the dignity is strongest; the dignity itself is held
    /// throughout the sign — which is why scoring tests the sign, not the degree.
    public static func exaltation(of body: CelestialBody) -> (sign: ZodiacSign, degree: Double)? {
        exaltationTable[body]
    }

    /// Fall is the exact opposite point of the exaltation.
    public static func fall(of body: CelestialBody) -> (sign: ZodiacSign, degree: Double)? {
        guard let e = exaltation(of: body) else { return nil }
        return (opposite(e.sign), e.degree)
    }

    /// The body exalted in this sign, if any. Eight signs have no exalted planet here
    /// (five once the node is excluded).
    public static func exaltationRuler(of sign: ZodiacSign) -> CelestialBody? {
        classicalBodies.first { exaltation(of: $0)?.sign == sign }
    }

    public static func fallRuler(of sign: ZodiacSign) -> CelestialBody? {
        exaltationRuler(of: opposite(sign))
    }

    // MARK: - Triplicity
    // Source: Ptolemy, *Tetrabiblos* I.18, as tabulated by Lilly, *Christian Astrology*
    // (1647), p. 104 — two rulers per triplicity (day, night), with Mars ruling the watery
    // triplicity in both sects.

    /// Day and night triplicity rulers, indexed by `Element`.
    private static let triplicityTable: [(day: CelestialBody, night: CelestialBody)] = [
        (.sun, .jupiter),     // fire
        (.venus, .moon),      // earth
        (.saturn, .mercury),  // air
        (.mars, .mars),       // water
    ]

    public static func triplicityRuler(of sign: ZodiacSign, sect: Sect) -> CelestialBody {
        let pair = triplicityTable[element(of: sign).rawIndex]
        return sect == .day ? pair.day : pair.night
    }

    /// Dorothean triplicity: three rulers per element (day, night, participating).
    ///
    /// Source: Dorotheus of Sidon, *Carmen Astrologicum* I.1 (Pingree ed.). Offered
    /// alongside — not instead of — the Ptolemaic pair above, because the two schemes
    /// disagree about water and mixing them silently is exactly the kind of error this
    /// module exists to prevent. `score` uses the Ptolemaic/Lilly pair.
    public static func dorotheanTriplicityRulers(
        of sign: ZodiacSign
    ) -> (day: CelestialBody, night: CelestialBody, participating: CelestialBody) {
        switch element(of: sign) {
        case .fire:  return (.sun, .jupiter, .saturn)
        case .earth: return (.venus, .moon, .mars)
        case .air:   return (.saturn, .mercury, .jupiter)
        case .water: return (.venus, .mars, .moon)
        }
    }

    // MARK: - Terms (bounds)
    // Source: the Egyptian terms as printed by Lilly, *Christian Astrology* (1647), p. 104
    // ("the Termes of the Planets"), the same table Ptolemy reports in *Tetrabiblos* I.21 as
    // the Egyptian bounds. Each entry is (ruler, end degree in sign); the start is the
    // previous end, and every sign's last end is 30.
    //
    // Cross-check that catches a transcription slip: the per-planet degree totals over the
    // whole zodiac are Saturn 57, Jupiter 79, Mars 66, Venus 82, Mercury 76 = 360. The test
    // suite asserts this against an oracle.

    private static let termTable: [[(CelestialBody, Double)]] = [
        [(.jupiter, 6), (.venus, 12), (.mercury, 20), (.mars, 25), (.saturn, 30)],   // Aries
        [(.venus, 8), (.mercury, 14), (.jupiter, 22), (.saturn, 27), (.mars, 30)],   // Taurus
        [(.mercury, 6), (.jupiter, 12), (.venus, 17), (.mars, 24), (.saturn, 30)],   // Gemini
        [(.mars, 7), (.venus, 13), (.mercury, 19), (.jupiter, 26), (.saturn, 30)],   // Cancer
        [(.jupiter, 6), (.venus, 11), (.saturn, 18), (.mercury, 24), (.mars, 30)],   // Leo
        [(.mercury, 7), (.venus, 17), (.jupiter, 21), (.mars, 28), (.saturn, 30)],   // Virgo
        [(.saturn, 6), (.mercury, 14), (.jupiter, 21), (.venus, 28), (.mars, 30)],   // Libra
        [(.mars, 7), (.venus, 11), (.mercury, 19), (.jupiter, 24), (.saturn, 30)],   // Scorpio
        [(.jupiter, 12), (.venus, 17), (.mercury, 21), (.saturn, 26), (.mars, 30)],  // Sagittarius
        [(.mercury, 7), (.jupiter, 14), (.venus, 22), (.saturn, 26), (.mars, 30)],   // Capricorn
        [(.mercury, 7), (.venus, 13), (.jupiter, 20), (.mars, 25), (.saturn, 30)],   // Aquarius
        [(.venus, 12), (.jupiter, 16), (.mercury, 19), (.mars, 28), (.saturn, 30)],  // Pisces
    ]

    /// The five terms of a sign, in degree order, spanning [0, 30).
    public static func terms(of sign: ZodiacSign) -> [Bound] {
        var start = 0.0
        var out: [Bound] = []
        for entry in termTable[sign.rawValue] {
            out.append(Bound(ruler: entry.0, sign: sign, start: start, end: entry.1))
            start = entry.1
        }
        return out
    }

    /// Every term of the zodiac, in longitude order (60 of them).
    public static var allTerms: [Bound] { ZodiacSign.allCases.flatMap(terms(of:)) }

    /// The term containing an ecliptic longitude. Total, because the table partitions
    /// every sign — the fallback exists only to keep the API non-optional.
    public static func term(at longitude: Double) -> Bound {
        let (sign, deg) = signAndDegree(longitude)
        let bounds = terms(of: sign)
        return bounds.first { deg >= $0.start && deg < $0.end } ?? bounds[bounds.count - 1]
    }

    public static func termRuler(at longitude: Double) -> CelestialBody {
        term(at: longitude).ruler
    }

    // MARK: - Faces (decans)
    // Source: Lilly, *Christian Astrology* (1647), p. 104 (the "Face" column); Ptolemy,
    // *Tetrabiblos* I.22 (decans). Ten degrees each, running in descending Chaldean order
    // (Saturn, Jupiter, Mars, Sun, Venus, Mercury, Moon) from Mars at 0° Aries. The table is
    // written out rather than generated so a transcription error and a generator error can
    // never cancel out; the suite asserts the two agree.

    /// Descending Chaldean (geocentric period) order — slowest to fastest.
    public static let chaldeanOrder: [CelestialBody] =
        [.saturn, .jupiter, .mars, .sun, .venus, .mercury, .moon]

    private static let faceTable: [[CelestialBody]] = [
        [.mars, .sun, .venus],          // Aries
        [.mercury, .moon, .saturn],     // Taurus
        [.jupiter, .mars, .sun],        // Gemini
        [.venus, .mercury, .moon],      // Cancer
        [.saturn, .jupiter, .mars],     // Leo
        [.sun, .venus, .mercury],       // Virgo
        [.moon, .saturn, .jupiter],     // Libra
        [.mars, .sun, .venus],          // Scorpio
        [.mercury, .moon, .saturn],     // Sagittarius
        [.jupiter, .mars, .sun],        // Capricorn
        [.venus, .mercury, .moon],      // Aquarius
        [.saturn, .jupiter, .mars],     // Pisces
    ]

    /// The three faces of a sign, in degree order.
    public static func faces(of sign: ZodiacSign) -> [Bound] {
        faceTable[sign.rawValue].enumerated().map { i, ruler in
            Bound(ruler: ruler, sign: sign, start: Double(i) * 10, end: Double(i) * 10 + 10)
        }
    }

    /// Every face of the zodiac, in longitude order (36 of them).
    public static var allFaces: [Bound] { ZodiacSign.allCases.flatMap(faces(of:)) }

    public static func face(at longitude: Double) -> Bound {
        let (sign, deg) = signAndDegree(longitude)
        return faces(of: sign)[min(Int(deg / 10), 2)]
    }

    public static func faceRuler(at longitude: Double) -> CelestialBody {
        face(at: longitude).ruler
    }
}

private extension EssentialDignities.Element {
    /// Position in `allCases` — the index the triplicity table is keyed by.
    var rawIndex: Int { EssentialDignities.Element.allCases.firstIndex(of: self)! }
}
