import Foundation

/// Plain-language meanings for every term this app puts on screen.
///
/// ## Why this exists separately from the entities
///
/// An `AppEntity` carries a **title** — `@Property(title: "Dignity")` — and a title is not a
/// meaning. Told only that a field is called "Dignity" and holds `−5`, a language model will invent
/// something plausible, and plausible-but-invented is the one failure this app cannot tolerate
/// beside an engine that is oracle-tested to arcminutes.
///
/// So the entity layer says *what a field is called* and this says *what it means*. The assistant
/// sends both, and is instructed to answer only from them.
///
/// ## Where the wording comes from
///
/// Transcribed from the prose that already exists in `docs/functions/*.md` and in the Kit's own doc
/// comments — not written fresh. Those documents are reviewed, cite their sources, and already
/// settle the contested points (which void-of-course definition, which peregrine convention). A
/// second, looser description written here would drift from them within a release.
///
/// ## The register
///
/// One sentence, written for someone who has never opened an astrology app, but *precise enough
/// that a practitioner would not correct it*. Both audiences read the same text; there is no
/// beginner mode. Where a convention is contested, the sentence says which one this app took —
/// silence there reads as authority the app does not have.
public enum Glossary {

    /// A term and what it means.
    public struct Entry: Hashable, Sendable {
        /// The exact token used in a `ScreenContext` field or value, so a lookup cannot miss.
        public let term: String
        public let meaning: String

        public init(term: String, meaning: String) {
            self.term = term
            self.meaning = meaning
        }
    }

    /// Look up a term, case-insensitively.
    public static func meaning(of term: String) -> String? {
        index[term.lowercased()]
    }

    /// Every entry whose term appears in `terms`, in the order given, skipping unknown ones.
    ///
    /// Callers pass the fields a screen actually names, so the assistant is sent the vocabulary for
    /// *this* screen rather than the whole dictionary — which would spend most of a 4,096-token
    /// budget explaining astrocartography to someone looking at the Moon.
    public static func entries(for terms: [String]) -> [Entry] {
        terms.compactMap { t in meaning(of: t).map { Entry(term: t, meaning: $0) } }
    }

    /// Terms that have no meaning here.
    ///
    /// ⚠️ Exists because `entries(for:)` **silently drops** what it cannot find, which makes any
    /// test of the form "every term in the schema is known" true by construction — the unknown term
    /// never reaches the schema to be checked. Verified by deliberately naming a term the glossary
    /// has never heard of and watching the guard stay green.
    ///
    /// A screen that names an undocumented term ships the model a heading with no meaning, which is
    /// when it starts inventing. Callers assert this is empty.
    public static func unknown(in terms: [String]) -> [String] {
        terms.filter { meaning(of: $0) == nil }
    }

    /// Every term the glossary knows. Used by the tests that assert no screen names a field the
    /// glossary cannot explain.
    public static var allTerms: [String] { all.map(\.term).sorted() }

    private static let index: [String: String] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.term.lowercased(), $0.meaning) })

    // MARK: - The vocabulary

    static let all: [Entry] = positions + aspectsAndHouses + dignities + events + moon + hours
        + frames + astrocarto + charts

    // ── Positions ────────────────────────────────────────────────────────────────
    private static let positions: [Entry] = [
        .init(term: "longitude", meaning:
            "Where a body sits around the 360° circle of the zodiac, measured from 0° Aries. It is a position along the ecliptic — not a distance and not a compass direction."),
        .init(term: "sign", meaning:
            "One of the twelve 30° divisions of that circle: Aries through Pisces. A body's sign is simply which slice its longitude falls in."),
        .init(term: "degree in sign", meaning:
            "How far a body has moved into its sign, 0° to 29°59′. A body at 29° is about to change sign."),
        .init(term: "speed", meaning:
            "How far a body moves in a day, in degrees. The Moon covers about 13° a day, Pluto a fraction of one."),
        .init(term: "retrograde", meaning:
            "A body appearing to move backwards through the zodiac as seen from Earth. It is an effect of the two orbits' relative motion, not a real reversal — marked ℞."),
        .init(term: "station", meaning:
            "The moment a body pauses before changing direction, either turning retrograde or turning direct again."),
    ]

    // ── Aspects and houses ───────────────────────────────────────────────────────
    private static let aspectsAndHouses: [Entry] = [
        .init(term: "aspect", meaning:
            "A significant angle between two bodies. This app uses the five classical ones: conjunction 0°, sextile 60°, square 90°, trine 120°, opposition 180°."),
        .init(term: "orb", meaning:
            "How far from exact an aspect is allowed to be and still count. A 2° orb on a square means 88°–92° qualifies; a smaller orb is a tighter, stronger aspect."),
        // Each names the angle AND the fraction of the circle it is. A bare "90° apart" is a
        // definition a newcomer can read without learning anything — the fraction is what makes the
        // pattern visible on a wheel. Deliberately no interpretation: this app describes what is
        // there and does not tell anyone what an aspect means for their life.
        .init(term: "conjunction", meaning:
            "Two bodies at the same longitude, 0° apart — occupying the same degree of the zodiac."),
        .init(term: "opposition", meaning:
            "Two bodies 180° apart, directly across the circle — half the zodiac between them."),
        .init(term: "square", meaning:
            "Two bodies 90° apart, a quarter of the circle. One of the five classical aspects."),
        .init(term: "trine", meaning:
            "Two bodies 120° apart, a third of the circle. One of the five classical aspects."),
        .init(term: "sextile", meaning:
            "Two bodies 60° apart, a sixth of the circle. One of the five classical aspects."),
        .init(term: "house", meaning:
            "One of twelve divisions of the local sky, measured from the horizon at a specific place and time. Houses need a birth time; the zodiac does not."),
        .init(term: "cusp", meaning: "The starting longitude of a house."),
        .init(term: "ascendant", meaning:
            "The degree of the zodiac rising on the eastern horizon at the moment and place in question. Abbreviated ASC; it is the first house cusp."),
        .init(term: "midheaven", meaning:
            "The degree culminating overhead, where the ecliptic meets the upper meridian. Abbreviated MC."),
        .init(term: "house system", meaning:
            "One of several competing methods for dividing the sky into twelve. They agree at the equator and diverge sharply at high latitude; Whole Sign always works because it is pure zodiac geometry."),
    ]

    // ── Dignities ────────────────────────────────────────────────────────────────
    private static let dignities: [Entry] = [
        .init(term: "dignity", meaning:
            "A classical score for how well-placed a body is in its sign, summed from five positive conditions and two negative ones. The values are transcribed from Ptolemy and Lilly, not computed from astronomy."),
        .init(term: "domicile", meaning:
            "A body in the sign it rules — the strongest placement, worth +5. Mars in Aries, for example."),
        .init(term: "exaltation", meaning: "A sign where a body is traditionally honoured, worth +4."),
        .init(term: "triplicity", meaning:
            "A body ruling one of the four elements by day or by night, worth +3."),
        .init(term: "term", meaning:
            "A subdivision of a sign into unequal degree-ranges, each ruled by a planet, worth +2."),
        .init(term: "face", meaning:
            "A 10° third of a sign, ruled in the Chaldean order — the same sequence that drives the planetary hours. Worth +1."),
        .init(term: "detriment", meaning:
            "A body in the sign opposite the one it rules, worth −5."),
        .init(term: "fall", meaning: "A body in the sign opposite its exaltation, worth −4."),
        .init(term: "peregrine", meaning:
            "A body holding none of the five dignities in the sign it occupies — a wanderer, worth −5. This app follows Lilly's convention and does not additionally charge a body already in detriment or fall, because that would count one weakness twice."),
    ]

    // ── Events ───────────────────────────────────────────────────────────────────
    private static let events: [Entry] = [
        .init(term: "ingress", meaning: "The moment a body crosses from one sign into the next."),
        .init(term: "lunation", meaning:
            "A new or full moon — the two moments when the Sun and Moon are aligned or opposite. The timeline lists them alongside ingresses and stations."),
        .init(term: "mundane aspect", meaning:
            "An aspect between two moving bodies in the current sky, as opposed to an aspect involving a birth chart."),
        .init(term: "synodic cycle", meaning:
            "One full cycle of a planet relative to the Sun — from conjunction, through its visibility as a morning or evening object, back to conjunction."),
        .init(term: "elongation", meaning:
            "The angle between a body and the Sun as seen from Earth. Greatest elongation is when an inner planet appears furthest from the Sun and is easiest to see."),
        .init(term: "transit", meaning:
            "A body in the current sky forming an aspect to a position in a birth chart."),
    ]

    // ── The Moon ─────────────────────────────────────────────────────────────────
    private static let moon: [Entry] = [
        .init(term: "phase", meaning:
            "Where the Moon is in its cycle of light, set by its angle from the Sun: new at 0°, first quarter at 90°, full at 180°, last quarter at 270°."),
        .init(term: "illumination", meaning:
            "The fraction of the Moon's visible disc that is lit, 0% at new and 100% at full."),
        .init(term: "waxing", meaning: "The lit fraction is growing, between new moon and full."),
        .init(term: "waning", meaning: "The lit fraction is shrinking, between full moon and new."),
        .init(term: "moonrise", meaning:
            "When the Moon crosses the horizon rising. It genuinely fails to occur on about one day a month at every latitude, because the lunar day runs roughly fifty minutes longer than the solar one — an absence here is a real answer, not missing data."),
        .init(term: "void of course", meaning:
            "The stretch between the Moon's last exact aspect and its change of sign. This app follows Lilly's traditional definition and counts aspects to the seven classical planets only, so its void periods start earlier — and run longer — than software that also counts Uranus, Neptune and Pluto."),
        .init(term: "synodic month", meaning:
            "The average time from one new moon to the next, 29.53 days. The true interval varies by about half a day either side."),
    ]

    // ── Planetary hours ──────────────────────────────────────────────────────────
    private static let hours: [Entry] = [
        .init(term: "planetary hour", meaning:
            "One twelfth of the time between sunrise and sunset, or between sunset and the next sunrise. These hours are not sixty minutes: in London in June a daytime hour runs about 82 minutes and a night hour about 38."),
        .init(term: "chaldean order", meaning:
            "The sequence Saturn, Jupiter, Mars, Sun, Venus, Mercury, Moon, by which each successive hour is ruled. Running it through a 24-hour day advances three places, which is why the weekdays are named in the order they are."),
        .init(term: "hour ruler", meaning: "The planet governing the current planetary hour."),
    ]

    // ── Frames ───────────────────────────────────────────────────────────────────
    private static let frames: [Entry] = [
        .init(term: "tropical", meaning:
            "The default zodiac, measured from the vernal equinox — the point where the Sun crosses the celestial equator in spring."),
        .init(term: "sidereal", meaning:
            "A zodiac measured from a fixed point among the stars instead of the equinox. Used in Vedic astrology."),
        .init(term: "ayanamsa", meaning:
            "The gap between the tropical and sidereal zodiacs, currently about 24° and growing by roughly 50 arcseconds a year. There is no single agreed value: Lahiri, Fagan–Bradley, Krishnamurti and Raman differ by up to a degree and a half, which is enough to move a body into a different sign."),
    ]

    // ── Astrocartography ─────────────────────────────────────────────────────────
    private static let astrocarto: [Entry] = [
        .init(term: "astrocartography", meaning:
            "A world map showing where on Earth each planet in a birth chart would have been angular — on the horizon or the meridian — at the moment of birth."),
        .init(term: "MC line", meaning: "Where a planet was culminating overhead. Drawn as a meridian, so it is a straight vertical line."),
        .init(term: "IC line", meaning: "Where a planet was directly underfoot, opposite the MC."),
        .init(term: "AC line", meaning: "Where a planet was rising on the eastern horizon. It curves, because the horizon does."),
        .init(term: "DC line", meaning: "Where a planet was setting on the western horizon."),
        .init(term: "circumpolar", meaning:
            "A body that never touches the horizon at a given latitude — so it has no rising or setting line there at all. The line is absent rather than clipped: drawing it to the edge of the map would invent a boundary that does not exist."),
    ]

    // ── Charts ───────────────────────────────────────────────────────────────────
    private static let charts: [Entry] = [
        .init(term: "natal chart", meaning:
            "The positions of the bodies at a person's moment and place of birth — a frozen instant, never scrubbed."),
        .init(term: "synastry", meaning: "Comparing two birth charts by the aspects between them."),
        .init(term: "composite", meaning:
            "A single chart built from the midpoints between two birth charts, treated as the chart of the relationship itself."),
        .init(term: "midpoint", meaning: "The halfway point between two positions on the zodiac circle."),
        .init(term: "progression", meaning:
            "A symbolic technique that advances a birth chart by a day for each year of life."),
        .init(term: "solar return", meaning:
            "The moment the Sun comes back to its exact birth longitude, once a year near the birthday."),
        .init(term: "unknown birth time", meaning:
            "Without a time the houses, Ascendant and Midheaven are undefined, and the Moon's position is uncertain by up to about 13°. The app reports a range instead of a false precision."),
        .init(term: "chart shape", meaning:
            "How the bodies are distributed around the wheel — bundle, bowl, bucket, seesaw and so on, after Marc Edmund Jones."),
    ]
}
