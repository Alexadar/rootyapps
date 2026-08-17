import SwiftUI

/// AISixteen Architecture — design tokens.
///
/// Shared DNA with AISixteen Wallpapers and AISixteen Studio; the deltas are the terracotta
/// accent, the bottom sheet and the preset card. Namespaced `ARC` to match the sibling's `WP`, so
/// a future shared module has no collision to resolve.
///
/// The handoff's `DesignSystem.swift` shipped five colours, three radii and one animation. Every
/// token below that it did NOT carry is marked, because each absence was a rule the mockups
/// silently failed to honour.
enum ARC {

    // ── colour ───────────────────────────────────────────────────────────────────────────────

    static let ink = Color(hex: 0x1D1A17)
    /// Terracotta. THIS APP ONLY — Studio is steel blue, Wallpapers has its own. The accent is
    /// half of how the three stay visibly distinct under Guideline 4.3.
    static let accent = Color(hex: 0xB4552D)
    // The Live Activity's lighter terracotta is NOT here. It lives in
    // `RedesignActivity.accentHex` — the one file compiled into both the app and the widget —
    // because the widget cannot see `ARC` at all. An `ARC.accentOnDark` alias existed for exactly
    // as long as it took to notice that nothing in the app target reads it either: the lock screen
    // is the only surface that wants that colour, and the lock screen is the widget's.
    /// What the accent drains to during a render. See AccentDrain.swift.
    static let neutral = Color(hex: 0x8A8378)
    static let canvas = Color(hex: 0xEFEBE4)
    static let canvasAlt = Color(hex: 0xF4F1EB)
    static let good = Color(hex: 0x3E8E5A)
    static let caution = Color(hex: 0xC8791F)

    /// ⚠️ ABSENT FROM THE HANDOFF SWIFT. Named only in the README's accessibility floor:
    /// "Reduce Transparency → opaque #F6F3ED with hairline borders (layout identical)". Nothing in
    /// the mockups responded to the setting at all.
    static let opaquePlate = Color(hex: 0xF6F3ED)

    static func hairline(opaque: Bool) -> Color {
        opaque ? Color.black.opacity(0.14) : Color.white.opacity(0.65)
    }

    // ── glass ────────────────────────────────────────────────────────────────────────────────

    /// The board's glass recipe is "white .60–.72, blur 18–24 pt, saturate 1.7, border white
    /// .60–.70". Only the border is here, because only the border is ours to set.
    ///
    /// ⚠️ **Fill, blur and saturation are NOT settable.** `.glassEffect(_:in:)` takes a `Glass`
    /// value whose whole API is `.regular` / `.tint(_:)` / `.interactive()`; the system renders the
    /// material and owns those numbers. They were previously declared here "so the treatment file
    /// has one place to read them from" — which was wrong, because nothing could read them and
    /// nothing did. Five tokens sitting unused look exactly like an unfinished feature, so they
    /// are gone rather than aspirational. The board's figures describe what the system produces;
    /// they are not instructions this app can follow.
    enum Glass {
        static let borderLow = 0.60
        static let borderHigh = 0.70
    }

    /// The milk veil over the forming image. ⚠️ Hardcoded inside `GeneratingView` in the handoff
    /// (`Color.white.opacity(0.22)`, `26 * (1 - fraction)`) rather than declared — which is why
    /// nothing could step it for Reduce Motion.
    enum Veil {
        static let opacity = 0.22
        static let blurStart: CGFloat = 26
        static let blurEnd: CGFloat = 0
        /// Reduce Motion turns the continuous ease into stepped stills.
        static let reduceMotionSteps = 3
    }

    // ── geometry ─────────────────────────────────────────────────────────────────────────────

    enum Radius {
        /// ⚠️ The handoff's token table lists "capsule 999" but no call site used a token — every
        /// one spelled `Capsule()`, next to raw 9 / 10 / 12 / 14 / 16 scattered over five files.
        static let capsule: CGFloat = 999
        static let sheet: CGFloat = 34
        static let card: CGFloat = 26
        static let preset: CGFloat = 18
        static let tile: CGFloat = 16
        static let chip: CGFloat = 14
        static let swatch: CGFloat = 9
    }

    enum Space {
        static let hair: CGFloat = 4
        static let tight: CGFloat = 8
        static let gap: CGFloat = 12
        static let grid: CGFloat = 16
        static let margin: CGFloat = 20
        static let wide: CGFloat = 24
        static let section: CGFloat = 32
    }

    /// ⚠️ The handoff named 44 pt in the accessibility floor and only the wipe knob hardcoded it.
    /// The mode-picker rows computed to about 31 pt and the prompt chips to about 26.
    static let minimumHitTarget: CGFloat = 44
    static let primaryCapsuleHeight: CGFloat = 52
    /// How far a full-bleed screen's own chrome must start below the top edge to clear the shell's
    /// floating Redesign · Library segment. The shell respects the safe area and this screen does
    /// not, so the two cannot be derived from one another — hence a named constant rather than a
    /// number repeated at each call site.
    static let shellSegmentClearance: CGFloat = 124

    /// The iPad direction rail. Wide enough for a two-column preset grid plus margins.
    static let railWidth: CGFloat = 360
    static let railWidthAX: CGFloat = 460

    // ── type ─────────────────────────────────────────────────────────────────────────────────

    /// The handoff says "SF Pro, px = pt" and then spells `.subheadline` / `.caption2` at every
    /// call site, which loses the actual sizes.
    ///
    /// These are `@ScaledMetric`-backed through `ARCText`, because `Font.system(size:weight:)` does
    /// NOT respond to Dynamic Type — the sibling's `Tokens.swift` calls that out as the single most
    /// common accessibility failure, and AX5 is a named requirement here.
    struct TextStyle {
        let size: CGFloat
        let weight: Font.Weight
        let relativeTo: Font.TextStyle

        static let title = TextStyle(size: 22, weight: .semibold, relativeTo: .title2)
        static let heading = TextStyle(size: 17, weight: .semibold, relativeTo: .headline)
        static let body = TextStyle(size: 17, weight: .regular, relativeTo: .body)
        static let cta = TextStyle(size: 17, weight: .semibold, relativeTo: .body)
        static let subheading = TextStyle(size: 15, weight: .semibold, relativeTo: .subheadline)
        static let secondary = TextStyle(size: 13, weight: .regular, relativeTo: .footnote)
        static let caption = TextStyle(size: 12, weight: .regular, relativeTo: .caption)
        static let captionStrong = TextStyle(size: 12, weight: .semibold, relativeTo: .caption)
        static let micro = TextStyle(size: 11, weight: .regular, relativeTo: .caption2)
        static let label = TextStyle(size: 11, weight: .bold, relativeTo: .caption2)
    }
}

/// Applies a `TextStyle` with Dynamic Type scaling that actually works.
struct ARCText: ViewModifier {
    let style: ARC.TextStyle
    let tabularNumbers: Bool
    @ScaledMetric private var scale: CGFloat = 1

    init(style: ARC.TextStyle, tabularNumbers: Bool) {
        self.style = style
        self.tabularNumbers = tabularNumbers
        _scale = ScaledMetric(wrappedValue: 1, relativeTo: style.relativeTo)
    }

    func body(content: Content) -> some View {
        var font = Font.system(size: style.size * scale, weight: style.weight)
        if tabularNumbers { font = font.monospacedDigit() }
        return content.font(font)
    }
}

extension View {
    /// The only way type is set in this app.
    ///
    /// `tabularNumbers` on anything that counts: a step counter whose digits change width makes
    /// the whole row jitter every second, which reads as instability in exactly the screen whose
    /// job is to feel calm for three minutes.
    func arcText(_ style: ARC.TextStyle, tabularNumbers: Bool = false) -> some View {
        modifier(ARCText(style: style, tabularNumbers: tabularNumbers))
    }
}

extension Color {
    /// Tokens are transcribed as hex verbatim from the design bundle, so they can be diffed
    /// against it without arithmetic.
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
