import SwiftUI
import WidgetKit

/// Complications for the standalone watch app. These are the **discovery surface**
/// — for a paid-once app with no companion listing, they are how it gets found and
/// how it justifies its slot every day.
///
/// The test for every candidate: **does the value actually change, and would
/// someone glance at it more than once a day?** Anything static is a wasted slot.
enum NebulaComplications {

    // MARK: - Ranked candidates
    //
    // ① RISING SIGN — lead with this. The Ascendant moves a sign roughly every two
    //   hours; it is the only value that changes *while you are looking at it*, and
    //   it exists only because this app computes real houses. On accessoryCorner the
    //   bezel curve is a GAUGE for progress through the current sign.
    // ② RETROGRADE — the most-checked fact in the domain. Glyphs + ℞ in amber; the
    //   gauge shows elapsed fraction, so "how much longer" needs no words.
    //   Inline: "♄︎ ℞ until 18 Nov".
    // ③ MOON PHASE + SIGN — drawn terminator at the real fraction (MoonPhaseDisc),
    //   never an emoji.
    // ④ NEXT EVENT + REAL DATE — "☽︎ → ♏︎ 30 Jul 04:12", exact to the minute. This
    //   is what makes it read as an almanac rather than a horoscope.
    // ⑤ SYNODIC PHASE — "☿︎ morning star · day 16 of 45". Niche, nobody else has it,
    //   ranked last because it moves slowly.
    //
    // Do NOT ship: a whole wheel, a full aspect list, or horoscope text. The app
    // generates none of those.

    enum Candidate: String, CaseIterable {
        case rising, retrograde, moon, nextEvent, synodic
    }

    // MARK: - Families and what actually fits
    //
    // accessoryCircular   72 pt  — one gauge, one glyph, one 9 pt qualifier. That is
    //                              the entire budget. Gauge style
    //                              .accessoryCircularCapacity.
    // accessoryCorner     80 pt  — glyph inboard + `.widgetLabel`. Rising uses the
    //                              label as a Gauge; others as ~20 characters of
    //                              text. The curve is SYSTEM-DRAWN: never hand-roll
    //                              it, and never place the glyph on the arc.
    // accessoryRectangular 158×57 — three lines, hard stop: kicker, glyph-led value,
    //                              dated footer. The flagship.
    // accessoryInline     1 line — the face's own font AND colour. Custom colour is
    //                              impossible, so design it monochrome-first. The one
    //                              family where words are worth the characters.
    // Smart Stack widget  158×72 — icon, kicker, big value, gauge, dated footer.
    //
    // X-Large was deliberately dropped: it is a single-complication face, so it
    // competes with the app's own Wheel screen instead of adding a discovery surface.

    static let families: [WidgetFamily] = [
        .accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline,
    ]

    // MARK: - Rendering modes — only one of them is yours
    //
    // Read `\.widgetRenderingMode`:
    //  .fullColor — a MINORITY of faces. Nebula palette as authored.
    //  .accented  — collapses to one hue ramp. Amber ℞ becomes a white ramp.
    //  .vibrant   — desaturated and blended into the face tint.
    //
    // Therefore every family is authored **glyph-and-gauge first**: the glyph names
    // the subject, the gauge carries the quantity, and colour is only ever
    // reinforcement. Nothing loses meaning when hue is stripped — which also keeps
    // it readable for the red-green colour-blind share of a practitioner audience.
    //
    //   @Environment(\.widgetRenderingMode) private var mode
    //   .widgetAccentedRenderingMode(.desaturated)   // on the phase disc
    //
    // Corner slots are POSITION-SPECIFIC: the gauge is concentric with the display's
    // own corner radius, so the curve mirrors per corner and the glyph always sits
    // inboard of it. The system handles the mirroring — you supply a Gauge, not a path.

    // MARK: - Timeline: nothing polls, nothing loads
    //
    // Entries are stamped with the exact instant each becomes valid — the second the
    // Ascendant changes sign, a planet stations, a body ingresses — and the system
    // renders them with the app not running.
    //
    //  • NEVER design a loading, refreshing or "last updated" state. They do not
    //    exist. A value is exact or it is absent.
    //  • No "about", no "~", no rounding language. The engine gives the precise
    //    second; entries land on it.
    //  • Rising changes sign ~every 2 h, so emit an entry per boundary plus
    //    intra-sign entries for the gauge (every ~6 min is ample and well inside
    //    the budget).
    static func entryDates(risingBoundaries: [Date], gaugeStep: TimeInterval = 360) -> [Date] {
        var out: [Date] = []
        for (i, b) in risingBoundaries.enumerated() {
            out.append(b)
            guard i + 1 < risingBoundaries.count else { break }
            var t = b.addingTimeInterval(gaugeStep)
            while t < risingBoundaries[i + 1] { out.append(t); t = t.addingTimeInterval(gaugeStep) }
        }
        return out
    }

    // MARK: - Two states you must design (data lives outside the widget's process)

    /// **No place set.** The Ascendant needs latitude AND longitude as well as time,
    /// unlike planetary positions — so without a saved place it cannot be computed.
    /// An error on a watch face is worse than useless: the user cannot act on it
    /// there. So degrade to a place-INDEPENDENT value instead.
    ///
    /// The footer is the only tell, and it names the fix ("no place set"), not the
    /// failure. Never render an error glyph, never render an empty slot.
    static func degrade(_ c: Candidate, hasPlace: Bool) -> Candidate {
        guard !hasPlace else { return c }
        switch c {
        case .rising: return .moon          // moon + retrograde need no coordinates
        default:      return c
        }
    }

    /// **Stale place.** Location comes from the shared App Group container and does
    /// not follow the user when they travel, so a rising value can be silently wrong
    /// by degrees.
    ///
    /// DECISION: **no badge on the face.** A warning glyph there is unactionable, it
    /// fires on every trip for a value most travellers still want, and it would
    /// train people to distrust a number that is usually right.
    ///
    /// Instead the place is always visible where it IS actionable: the Now screen
    /// gives up its own title to show the place name ("LOS ANGELES", top of screen,
    /// every glance), so the discrepancy is discoverable in one tap from the
    /// complication that led there. The screen title was the cheapest thing on the
    /// layout to spend, and it cost no vertical space on a screen already full at
    /// 215 pt.
    static let badgeStalePlace = false

    // MARK: - Localisation
    //
    // Locale resolves at RENDER TIME from the App Group, not from the system. A
    // widget extension is a separate process and would otherwise show English
    // despite the in-app language picker.
    //
    //   let code = UserDefaults(suiteName: appGroup)?.string(forKey: "language")
    //   let bundleLocale = Locale(identifier: code ?? Locale.current.identifier)
    //
    // Every complication string must survive all 17 languages in the SMALLEST
    // family. The reason this is achievable: four of the five candidates are glyphs
    // and numbers only, so they are byte-identical in every locale. Inline is the
    // only place words appear ("until", "morning star") — budget them there and
    // nowhere else.
    static let appGroup = "group.com.rootyapps.ephemeris"
}
