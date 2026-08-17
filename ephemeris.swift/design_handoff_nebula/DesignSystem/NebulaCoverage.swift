import SwiftUI

/// The coverage redesign — navigation and surface conventions that take the app from the
/// shipped structure to one covering all 16 functions.
///
/// Reference: `reference/Ephemeris Sky (Coverage Redesign).html`.
///
/// Settled decisions (breaking any is a defect, not a choice):
///  - `MomentLens` returns to FOUR cases (chart · table · aspects · houses).
///    `MomentLens.skyLenses` is deleted; `chartLenses` becomes the only list.
///    Moon and Hours are NOT lenses — they read a place over time, not a chart
///    at an instant (`SkyMoment.place` is the code's own proof) — they are Sky
///    DESTINATIONS, pushed from live-value rows beneath the readout.
///  - The fourth tab seat stays EMPTY. `LegacyTab` never learns a fourth case;
///    EPHEMERIS_TAB 0–5 land on the same pixels.
///  - EPHEMERIS_LENS keeps every value: `moon` / `hours` now push their
///    destination on launch instead of selecting a segment.
///  - Export is an ACTION: one ⤴ per exportable surface (timeline → .ics/JSON,
///    chart detail → chart JSON, moon calendar → phase events), never a submenu.
///    The sheet states count + range BEFORE anything happens. Nothing uploads.
///  - Gate 0 first-run: Sky leads with the moon hero (phase · % · days to full,
///    alerts link into Settings — the ONLY place permission is requested), then
///    teaching rows. Nothing auto-presents.
///
/// ⚠️ Moon disc authority: the shipped `ephemeris/Views/MoonDisc.swift` is THE
/// component — hemisphere-correct via `litOnRight(waxing:latitude:)`, elliptical
/// terminator, 5 tests. The former `DesignSystem/MoonPhaseDisc.swift` (no
/// latitude input, northern-only) is DELETED from this handoff. Every disc call
/// site must pass a latitude; where none exists (widgets, gate 0), the phase is
/// text — name, percentage, waxing/waning — never a drawn or emoji moon.
enum NebulaCoverage {

    // MARK: - Sky destinations (the two rows beneath the readout)
    //
    // Both rows carry a LIVE value so they still glance like lenses:
    //  Moon  → disc (place known) or ☽ (gate 0) · "23% · full in 10 d"
    //  Hours → current ruler glyph · "Mars · 64 min left" (place known)
    //          or "Planetary hours divide the day at a place" + place actions.
    enum SkyDestination: String, CaseIterable, Identifiable {
        case moon, hours
        var id: String { rawValue }
        var titleKey: String { "sky.dest.\(rawValue)" }   // L.string(_, locale:)
    }

    // MARK: - Planetary hours ring
    //
    // The ring is unequal BY CONSTRUCTION: twelve day segments span sunrise→
    // sunset, twelve night segments the rest. Equal segments misstate the
    // mathematics. Sunrise and sunset are the only fixed points (markers, cyan).
    // Day arcs warm (#FFD98A at 45%), night arcs violet (#8A7DC9 at 40%),
    // current hour amber #FFB020 with glow, remaining minutes in the centre.
    // ‹ › walk the sequence without leaving the ring.
    static let hourDay = Color(rgbHex: 0xFFD98A).opacity(0.45)
    static let hourNight = Color(rgbHex: 0x8A7DC9).opacity(0.40)
    static let hourCurrent = Color(rgbHex: 0xFFB020)
    static let hourMarker = Color(rgbHex: 0x35E7FF)

    /// Polar honesty: above the polar circles `RiseSet` returns nil — the ring
    /// is ABSENT (never 24 fabricated segments) and the card names the real
    /// resume date. Same rule for moonrise/moonset on the calendar: a dash plus
    /// the next real time.
    static let polarStateIsACard = true

    // MARK: - Void-of-course (moon-calendar day detail)
    //
    // VoC ships as a Settings toggle `settings.voidOfCourse` (OFF by default) plus an
    // overlay in the moon-calendar DAY DETAIL. The redesign moves the calendar from a
    // lens to a full-screen destination, so the overlay's home is the day-detail card
    // reached by tapping a date (identifier `moon.detail.void`) — NOT a per-screen
    // toggle on the calendar itself.
    //
    //  • Toggle ON, day HAS a void: a row in the day detail —
    //      "Void-of-course 14:12 → 23:47, then enters ♑"
    //    start = the Moon's last exact aspect before it leaves the sign; end = ingress.
    //  • Toggle ON, day has NO void: `moon.detail.voidNone` shows the honest line
    //      "No void-of-course today" — a stated absence, never a blank or a dropped row
    //    (same rule as the polar / no-moonset states).
    //  • Toggle OFF: the overlay is absent from every day detail and the calendar reads
    //    exactly as it does today — no dimmed control, no placeholder.
    //
    // NAME THE BODY SET ON SCREEN. The engine's default is Lilly's traditional SEVEN
    // bodies (☉ ☽ ☿ ♀ ♂ ♃ ♄) — no outers. A practitioner comparing against software
    // that counts ♅ ♆ ♇ will see a LATER void start in THEIR app; that is a real disagreement
    // between two defensible definitions, not a bug. The day detail carries the caption
    // "traditional 7 bodies (Lilly)" so the difference is legible, never implicit.
    static let voidOfCourseDefaultOn = false
    enum VoidBodySet { case lillySeven }          // ☉☽☿♀♂♃♄ — the shipped default
    static let voidBodySet: VoidBodySet = .lillySeven

    // MARK: - Export
    //
    // Once shipped the payload is a public contract: ISO 8601 instants carrying
    // their zone, byte-deterministic ordering, schema version in the payload
    // (v1). Renaming a field is a migration decision.
    static let exportSchemaVersion = 1

    // MARK: - Widgets
    //
    // Moon widget (iOS/macOS): stays TEXT-ONLY — gate 0 → no location → no
    // hemisphere; every drawn phase is handed.
    // Hours widget (systemSmall + accessoryInline "♂ until 10:45"): designed,
    // GATED on the App Group migration being its own scoped commit (declare the
    // group on app + widget, migrate SharedStore keys once behind a version
    // flag, prove parity in tests). It never rides along in a widget PR.
    // No-location state: "Open Ephemeris to set a place" — never a fabricated
    // hour. Both bundles set .containerBackground(.clear, for: .widget).
    static let hoursWidgetGatedOnAppGroup = true

    // MARK: - Accessibility identifiers (new leaves only — existing ids survive)
    enum A11y {
        static let moonRow = "sky.moon.row"
        static let hoursRow = "sky.hours.row"
        static let firstRunHero = "sky.firstrun.hero"
        static let moonCalendar = "moon.calendar"
        static let hoursRing = "hours.ring"
        static let exportEvents = "export.events"
        static let exportChart = "export.chart"
        static let exportMoon = "export.moon"
        static let hoursWidget = "widget.hours"
        static let settingVoid = "settings.voidOfCourse"
        static let voidOverlay = "moon.detail.void"
        static let voidNone = "moon.detail.voidNone"
    }
}
