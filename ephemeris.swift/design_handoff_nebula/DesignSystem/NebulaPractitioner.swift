import SwiftUI

/// The practitioner layer — UI conventions for the eight EphemerisKit features
/// surfaced inside **Charts** (synastry, progressions, returns, composite,
/// dignities, chart analysis, midpoints, astrocartography).
///
/// Reference: `reference/Ephemeris Sky (Practitioner Layer).html`.
///
/// Placement contract (settled — do not redesign):
///  - No new top-level section. The fourth navigation seat stays EMPTY.
///    LegacyTab.destination(for:) and EPHEMERIS_TAB 0–5 are untouched.
///  - The chart detail grows exactly TWO surfaces:
///      1. the Bi-wheel segment's outer-ring source control (BiWheelSource),
///      2. the ⚯ Compare button → pairing view (Synastry · Composite).
///    Dignities / shape / balances / midpoints are cards in the existing
///    Analysis segment; Returns is the existing fourth segment;
///    Astrocartography is a row beneath the wheel.
///  - Everything renders through the ONE shared MomentReadout. A return is a
///    Moment, a progressed chart is a Moment at the progressed date, a
///    composite is a synthetic Moment. Never a second table/wheel/aspect list.
enum NebulaPractitioner {

    // MARK: - Bi-wheel outer-ring source
    //
    // One control, four features. Each case is just a different Moment fed to
    // the same readout. Chip row sits directly under the segment control.
    enum BiWheelSource: String, CaseIterable, Identifiable {
        case transits, progressed, `return`, partner
        var id: String { rawValue }
        /// Titles resolve through L.string(_, locale:) — NEVER a bare
        /// LocalizedStringKey; macOS title chrome does not inherit \.locale.
        var titleKey: String { "biwheel.source.\(rawValue)" }
    }

    /// Outer (comparison) ring tint. Natal stays the standard planet glyph
    /// style; the outer ring is magenta-family so the two rings never blur.
    static let outerRingGlyph = Color(rgbHex: 0xFF9DC6)
    static let outerRingStroke = Color(rgbHex: 0xFF4D9D).opacity(0.45)

    // MARK: - Pairing (the two-chart problem)
    //
    // The library NEVER grows multi-select. Pairing is directional: from a
    // chart detail, ⚯ Compare opens a one-tap partner picker (the open chart
    // is already side A). Picking side B pushes ONE pairing view titled
    // "A ⚯ B" with two segments — Synastry · Composite — two readings of the
    // same pair, not two features.
    static let compareGlyph = "⚯\u{FE0E}"

    /// Recent pairs float to the top of the picker (second consultation of a
    /// couple = two taps). Persisted as chart-file identifier pairs.
    static let recentPairsLimit = 5

    /// Side badges on synastry rows: A = the chart the user came from.
    static let sideA = Color(rgbHex: 0xFF4D9D)   // magenta
    static let sideB = Color(rgbHex: 0x35E7FF)   // cyan

    // MARK: - Honest missing-data treatments
    //
    // The houses rule generalises: COMPUTE what the data allows, EXPLAIN what
    // it doesn't, never quietly assume noon. Amber is the one warning hue.
    //
    //  unknown birth time →
    //   synastry      Moon rows tagged RANGE (day min–max orb); contacts to
    //                 that side's angles/houses excluded, reason stated inline.
    //   progressions  progressed angles excluded; progressed Moon as day-range.
    //   composite     planets compute exactly (midpoints of positions);
    //                 houses/angles replaced by an amber card naming the
    //                 missing input and offering time entry.
    //   returns       the whole segment is one honest card — returns need the
    //                 exact moment; offers time entry.
    //   dignities     works from longitudes; if the Moon could cross a sign
    //                 boundary within the day, both candidate scores show.
    //   analysis      always computes; angles simply excluded from balances.
    //   midpoints     positions only — unaffected.
    //   astrocarto    honestly unavailable: angles are undefined. The row stays
    //                 visible, explains why, offers time entry. Never a noon map.
    //
    //  single saved chart → the partner picker shows the library empty-state
    //   illustration + "Save another chart", not an empty table.
    //
    //  return outside the ephemeris window → the row is PRESENT but disabled
    //   and names the window; the list never pretends the return doesn't exist.
    static let warn = Color(rgbHex: 0xFFB020)
    static let warnFill = Color(rgbHex: 0xFFB020).opacity(0.08)
    static let warnBorder = Color(rgbHex: 0xFFB020).opacity(0.35)

    /// "RANGE" tag on synastry/progressed Moon rows against an untimed chart.
    /// Localized through L.string("practitioner.range", locale:).
    static let rangeTagFont = Font.system(size: 9, weight: .bold)

    /// Ephemeris coverage; format the bound into the disabled row's subtitle.
    static let ephemerisWindow = 1800...2100

    // MARK: - Midpoints
    //
    // A card in the Analysis segment (plus a jump-row on the hub). Defaults to
    // the personal-planet pairs; "All 78" is one tap. Ambiguous pairs
    // (bodies 180° apart, Midpoints.isAmbiguous) are BOTH listed, both
    // labelled, neither hidden.
    static let personalPairsFirst = true
    static let midpointAmbiguousRowFill = Color(rgbHex: 0xFFB020).opacity(0.05)

    // MARK: - Watch verdict
    //
    // Seven of the eight do NOT belong on the watch: synastry, composite,
    // progressions, dignities, chart analysis, midpoints and astrocartography
    // are consultation tools — every one fails the complication test. The one
    // spillover is Returns as an Events row ("☉ return · 12 Mar 04:22"),
    // glyph-led and exact-dated, only when a default chart is set on the
    // phone; with none set the row simply isn't there.
    static let watchShipsReturnsEventRow = true

    // MARK: - Accessibility identifiers (new leaves only — existing ids survive)
    enum A11y {
        static let compare = "chart.compare"
        static let pairingSynastry = "pairing.synastry"
        static let pairingComposite = "pairing.composite"
        static let biwheelSource = "biwheel.source"
        static let analysisMidpoints = "analysis.midpoints"
        static let astrocartography = "chart.astrocartography"
        static let returnsRow = "returns.row"
    }
}

// MARK: - Shared row chrome

/// Amber explanation card — the standard "why this can't compute" surface.
/// Body text is prose (localized); the fix is a tappable accent phrase.
struct HonestStateCard: View {
    let title: String      // e.g. L.string("composite.noHouses", locale:)
    let body_: String      // names the missing input
    var fixLabel: String?  // e.g. "Add Marko's time" — nil when unactionable
    var onFix: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(NebulaPractitioner.warn)
            (Text(body_) + Text(fixLabel.map { "  \($0)" } ?? "")
                .foregroundColor(NebulaPalette.accentCyan))
                .font(.system(size: 11.5))
                .lineSpacing(3)
                .foregroundStyle(NebulaPalette.textPrimary.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(NebulaPractitioner.warnFill,
                    in: .rect(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(NebulaPractitioner.warnBorder, lineWidth: 0.5))
        .contentShape(.rect)
        .onTapGesture { onFix?() }
    }
}
