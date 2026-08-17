import SwiftUI
import EphemerisKit

/// The practitioner layer — shared conventions for the seven Kit features that live inside Charts.
///
/// The design contract is `design_handoff_nebula/DesignSystem/NebulaPractitioner.swift` and
/// `reference/Ephemeris Sky (Practitioner Layer).html`. That folder is a handoff, not a build
/// input; this is the compiled counterpart and the two are expected to agree.
///
/// **One deliberate divergence from the handoff.** It specifies `ephemerisWindow = 1800...2100`.
/// Nothing in this project verifies anything before 1900: `AccuracyTests` samples nine epochs
/// starting at 1900, no oracle in the corpus carries an earlier value, and the only mention of
/// 1800 is a comment about Pluto's series being *documented* that far — a claim the tests never
/// exercise below 2075. Since this constant is printed to the user as a coverage bound, shipping
/// 1800 would assert a century the app has never checked. See `ephemerisWindow` below.
enum NebulaPractitioner {

    // MARK: - Bi-wheel outer-ring source
    //
    // One control, four features. Each case is only a different Moment fed to the same
    // `MomentReadout`, which is what keeps transits, progressions, returns and synastry from
    // growing four private copies of the wheel.

    enum BiWheelSource: String, CaseIterable, Identifiable, Sendable {
        case transits, progressed, chartReturn, partner

        public var id: String { rawValue }

        /// Resolved through `L.string(_, locale:)` at the call site rather than exposed as a
        /// `LocalizedStringKey`: these titles reach a segmented control inside a navigation stack,
        /// and on macOS that chrome does not inherit the view's `\.locale` override.
        var titleKey: String {
            switch self {
            case .transits:    "Transits"
            case .progressed:  "Progressed"
            case .chartReturn: "Return"
            case .partner:     "Partner"
            }
        }
    }

    /// Outer (comparison) ring tint. Natal keeps the standard glyph styling; the outer ring is
    /// magenta-family so a bi-wheel never reads as one undifferentiated tangle of glyphs.
    static let outerRingGlyph = Color(rgbHex: 0xFF9DC6)
    static let outerRingStroke = Color(rgbHex: 0xFF4D9D).opacity(0.45)

    // MARK: - Pairing

    /// The compare affordance. Variation-selector-15 pins the text presentation — without it the
    /// glyph renders as a colour emoji on some platforms and stops matching the toolbar's line art.
    static let compareGlyph = "⚯\u{FE0E}"

    /// Recent pairs float to the top of the partner picker, so the second consultation of a couple
    /// is two taps rather than a search.
    static let recentPairsLimit = 5

    /// Side badges. A is always the chart the user came from — pairing is directional.
    static let sideA = Color(rgbHex: 0xFF4D9D)
    static let sideB = Color(rgbHex: 0x35E7FF)

    // MARK: - Honest missing-data treatment

    /// The one warning hue. Amber rather than red: a missing birth time is a limit on what can be
    /// said, not an error the user made.
    static let warn = Color(rgbHex: 0xFFB020)
    static let warnFill = Color(rgbHex: 0xFFB020).opacity(0.08)
    static let warnBorder = Color(rgbHex: 0xFFB020).opacity(0.35)

    /// The `RANGE` tag drawn beside an orb the unknown birth time leaves undetermined.
    static let rangeTagFont = Font.system(size: 9, weight: .bold)

    /// Years the ephemeris is *verified* across — printed to the user, so it states what the
    /// oracle corpus actually covers rather than what the series is documented to tolerate.
    static let ephemerisWindow = 1900...2100

    // MARK: - Midpoints

    /// Personal-planet pairs lead the midpoint list; the full set is one tap away.
    static let personalPairsFirst = true
    static let midpointAmbiguousRowFill = Color(rgbHex: 0xFFB020).opacity(0.05)

    // MARK: - Accessibility identifiers (new leaves only — existing ids are untouched)

    enum A11y {
        static let facet = "chart.facet"
        static let compare = "chart.compare"
        static let biwheelSource = "biwheel.source"
        static let pairingSynastry = "pairing.synastry"
        static let pairingComposite = "pairing.composite"
        static let partnerPicker = "pairing.partnerPicker"
        static let analysisDignities = "analysis.dignities"
        static let analysisShape = "analysis.shape"
        static let analysisBalances = "analysis.balances"
        static let analysisMidpoints = "analysis.midpoints"
        static let returnsList = "returns.list"
        static let returnsRow = "returns.row"
    }
}

// MARK: - Shared chrome

/// The standard "why this cannot compute" surface.
///
/// The houses rule generalised: compute what the data allows, explain what it does not, and never
/// quietly assume noon. Every feature that can be blocked by a missing birth time renders this
/// rather than an empty view — an empty view reads as "nothing here", which is a different and
/// false statement from "this needs a birth time".
struct HonestStateCard: View {
    let title: String
    let explanation: String
    /// Nil when there is nothing the user could do about it.
    var fixLabel: String? = nil
    var onFix: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: title)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(NebulaPractitioner.warn)
            Text(verbatim: explanation)
                .font(.system(size: 11.5))
                .lineSpacing(3)
                .foregroundStyle(NebulaPalette.textPrimary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            if let fixLabel {
                Text(verbatim: fixLabel)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(NebulaPalette.accentCyan)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(NebulaPractitioner.warnFill,
                    in: .rect(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(NebulaPractitioner.warnBorder, lineWidth: 0.5))
        .contentShape(.rect)
        .onTapGesture { onFix?() }
        // Combined before naming, or macOS fuses the children itself and synthesises a joined
        // identifier that matches nothing — the trap that broke every natal test on macOS.
        .accessibilityElement(children: .combine)
    }
}

/// The `RANGE` tag: an orb the unknown birth time leaves undetermined, shown as its bounds.
struct RangeTag: View {
    let range: Uncertainty.OrbRange
    var body: some View {
        HStack(spacing: 4) {
            Text("RANGE")
                .font(NebulaPractitioner.rangeTagFont)
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(NebulaPractitioner.warnFill, in: .rect(cornerRadius: 3))
                .foregroundStyle(NebulaPractitioner.warn)
            Text(verbatim: String(format: "%.1f–%.1f°", range.min, range.max))
                .font(.caption).monospacedDigit()
                .foregroundStyle(NebulaPalette.textSecondary)
        }
    }
}
