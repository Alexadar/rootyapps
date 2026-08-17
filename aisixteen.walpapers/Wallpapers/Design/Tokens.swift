import SwiftUI

/// The design bundle's tokens, verbatim.
///
/// The handoff is high-fidelity: colours, sizes, radii and spacing are final and its HTML pixels map
/// 1:1 to points. Every value here is transcribed from `1f` (design system) and `1g` (legibility
/// proof); nothing is invented, and nothing in a view should ever spell a colour or a radius itself.
enum WP {

    // MARK: Colour

    /// The single tint in the app. Tinted glass sits at 66 % over dark content and 75 % over light —
    /// the deeper value is not decoration, it is what keeps white label text at 4.5:1 over a pale
    /// wallpaper (bundle 1g).
    static let accent = Color(hex: 0x0A84FF)

    /// Paired with a word or a glyph, never carrying meaning alone.
    static func success(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x4CD964) : Color(hex: 0x1F9D47)
    }
    static func destructive(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xFF7878) : Color(hex: 0xC83636)
    }

    /// Ink, in three weights. Light theme is near-black; dark theme is white at the same opacities.
    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : Color(hex: 0x1A1A1E)
    }
    /// Secondary copy. 55 % on light, 65 % on dark — dark needs more because white on a dark plate
    /// loses apparent weight faster.
    static func ink2(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.65) : Color(hex: 0x1A1A1E).opacity(0.55)
    }
    /// Captions, counts, placeholders.
    static func ink3(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.45) : Color(hex: 0x1A1A1E).opacity(0.45)
    }
    /// A disabled label. Reads as disabled by weight *and* opacity, never by colour alone.
    static func inkDisabled(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.35) : Color(hex: 0x1A1A1E).opacity(0.35)
    }

    /// The opaque substitutes used when Reduce Transparency is on. Same geometry, no material.
    static func opaquePlate(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x2C2E38) : Color(hex: 0xF2F0EB)
    }
    /// The tinted plate under Reduce Transparency — darkened so white text still clears 4.5:1
    /// without the glass underneath to help.
    static let opaqueAccent = Color(hex: 0x0A6FD6)

    /// The hairline that draws a plate's edge. Bright on glass; a low-contrast rule when opaque.
    static func hairline(_ scheme: ColorScheme, opaque: Bool = false) -> Color {
        if opaque { return scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.10) }
        return scheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.80)
    }

    // MARK: Background

    /// First launch, before there is a wallpaper to blur behind the controls.
    static let dawn = [Color(hex: 0xFDFCFA), Color(hex: 0xEFECE5), Color(hex: 0xE2DED4)]
    static let lightBackground = [Color(hex: 0xF4F2EE), Color(hex: 0xE9E6DF)]
    static let darkBackground = [Color(hex: 0x171A26), Color(hex: 0x0D0F16)]
    /// The Mac window's warm paper.
    static let macPaper = [Color(hex: 0xF7F5F0), Color(hex: 0xE9E6DF)]

    // MARK: Geometry

    /// Concentric, outermost first. A radius that is not on this ladder is a mistake.
    enum Radius {
        /// **A reference, not a value this app applies.** The device owns its display corner and the
        /// system owns a Mac window's; there is no API that sets either. It is the rung the rest of
        /// the ladder is measured down from, so deleting it would leave "concentric, outermost
        /// first" describing a ladder with no top.
        ///
        /// It will therefore never have a call site, and a sweep for unreferenced tokens will flag
        /// it forever. That is correct and it is not a gap — the distinction worth keeping is
        /// *unused* (a missing call site) versus *unusable* (something the system owns). Only the
        /// first is work.
        static let screen: CGFloat = 48
        static let sheet: CGFloat = 38
        static let frame: CGFloat = 32
        static let card: CGFloat = 28
        static let plate: CGFloat = 22
        static let tile: CGFloat = 22
    }

    enum Space {
        static let hair: CGFloat = 4
        static let tight: CGFloat = 8
        static let gap: CGFloat = 12
        static let grid: CGFloat = 16
        static let margin: CGFloat = 24
        static let section: CGFloat = 32
    }

    /// Everything tappable. Not a suggestion — the bundle states it as a floor.
    static let minimumHitTarget: CGFloat = 44
    static let primaryCapsuleHeight: CGFloat = 56
    static let pillHeight: CGFloat = 44
    static let compactPillHeight: CGFloat = 38
    // `circleButton = 56` was deleted. Every circular button in the app is 52 (`smallCircleButton`)
    // or the 44 pt floor, so it was a second name for `primaryCapsuleHeight`'s number that nothing
    // needed — and a size ladder with an unreachable rung invites someone to reach for it.
    static let smallCircleButton: CGFloat = 52
}

// MARK: - Type

/// The bundle's type ramp. Sizes are points at the default Dynamic Type size; `wpFont` scales them.
struct WPTextStyle {
    let size: CGFloat
    let weight: Font.Weight
    /// What this scales against. Picking the right one matters: a caption that scaled like a title
    /// would overrun its plate at the largest accessibility sizes.
    let relativeTo: Font.TextStyle

    static let largeTitle   = WPTextStyle(size: 34, weight: .bold, relativeTo: .largeTitle)
    static let screenTitle  = WPTextStyle(size: 28, weight: .bold, relativeTo: .title)
    static let gateHeadline = WPTextStyle(size: 30, weight: .bold, relativeTo: .title)
    static let cardHeading  = WPTextStyle(size: 21, weight: .semibold, relativeTo: .title3)
    /// The one deliberately oversized style — the prompt the user is writing is the primary object
    /// on the Create screen, and it should feel like it.
    static let prompt       = WPTextStyle(size: 19, weight: .regular, relativeTo: .body)
    static let button       = WPTextStyle(size: 17, weight: .semibold, relativeTo: .body)
    static let body         = WPTextStyle(size: 16, weight: .regular, relativeTo: .body)
    static let secondary    = WPTextStyle(size: 15, weight: .regular, relativeTo: .subheadline)
    static let control      = WPTextStyle(size: 15, weight: .medium, relativeTo: .subheadline)
    static let caption      = WPTextStyle(size: 13, weight: .regular, relativeTo: .caption)
    static let footnote     = WPTextStyle(size: 12.5, weight: .regular, relativeTo: .caption)
}

/// Applies a token text style, scaled for Dynamic Type.
///
/// `Font.system(size:weight:)` does **not** scale — a screen built from it ignores the user's text
/// size entirely, which is the single most common accessibility failure in a hand-tokenised design.
/// `@ScaledMetric` is what makes fixed point sizes honour the setting.
private struct WPFontModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let monospacedDigits: Bool

    init(_ style: WPTextStyle, monospacedDigits: Bool) {
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeTo)
        self.weight = style.weight
        self.monospacedDigits = monospacedDigits
    }

    func body(content: Content) -> some View {
        content.font(monospacedDigits
                     ? .system(size: size, weight: weight).monospacedDigit()
                     : .system(size: size, weight: weight))
    }
}

extension View {
    /// - Parameter tabularNumbers: for anything that counts — byte totals, transfer rates,
    ///   "Step 9 of 28", wallpaper counts. Proportional digits make those labels shimmy as they
    ///   change, which reads as instability in exactly the places the app is asking to be trusted.
    func wpFont(_ style: WPTextStyle, tabularNumbers: Bool = false) -> some View {
        modifier(WPFontModifier(style, monospacedDigits: tabularNumbers))
    }
}

// MARK: - Hex

extension Color {
    /// The bundle states colours as hex. Transcribing them by eye into RGB triples is how a design
    /// drifts, so they are written here exactly as they appear in the handoff.
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
