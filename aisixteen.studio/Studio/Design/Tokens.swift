import SwiftUI

/// The design bundle's tokens, verbatim.
///
/// The handoff is high-fidelity: colours, sizes, radii and spacing are final and its HTML pixels map
/// 1:1 to points. Every value here is transcribed from the board's token table (`1m`) and the
/// accessibility variants (`1k`); nothing is invented, and nothing in a view should ever spell a
/// colour or a radius itself.
///
/// ### Family, not copy
///
/// The glass recipe, the spacing ladder and the type ramp are the same system as AISixteen
/// Wallpapers — deliberately, they are one family. The **accent** is not: Wallpapers is a bright
/// system blue, Studio is a quiet steel blue, because a filter-app accent on a photo editor makes
/// every screen look like a filter app.
enum ST {

    // MARK: Colour

    /// `oklch(52% 0.09 245)`. Enhance and Save capsules, the strength fill, the selected mask
    /// overlay. Calm and photographic on purpose — it sits next to the user's photo all day.
    static let accent = Color(hex: 0x29496B)

    /// One step darker (`oklch(45% 0.10 245)`), for Reduce Transparency. Without the glass beneath
    /// it, the lighter accent does not hold 4.5:1 under white label text (`1k`).
    static let opaqueAccent = Color(hex: 0x1F3A57)

    /// The canvas behind everything, before a photo is loaded. Warm paper, not white.
    static let canvas = Color(hex: 0xF4F3F0)
    static let canvasGradient = [Color(hex: 0xF7F6F4), Color(hex: 0xEDEBE6)]
    /// The Mac window's paper.
    static let macPaper = [Color(hex: 0xF7F6F4), Color(hex: 0xE9E6DF)]

    /// Ink, in three weights.
    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : Color(hex: 0x1A1A1A)
    }
    /// Secondary copy. 55 % on light, 65 % on dark — dark needs more, because white on a dark plate
    /// loses apparent weight faster.
    static func ink2(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.65) : Color(hex: 0x1A1A1A).opacity(0.55)
    }
    /// Captions, counts, placeholders.
    static func ink3(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.45) : Color(hex: 0x1A1A1A).opacity(0.45)
    }
    /// Reads as disabled by weight *and* opacity, never by colour alone.
    static func inkDisabled(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.35) : Color(hex: 0x1A1A1A).opacity(0.35)
    }

    static func destructive(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xFF7878) : Color(hex: 0xC83636)
    }

    /// The opaque substitute used when Reduce Transparency is on: `#F7F6F4` plus a hairline (`1k`).
    /// Same geometry, no material.
    static func opaquePlate(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x2A2C33) : Color(hex: 0xF7F6F4)
    }

    /// The hairline that draws a plate's edge. Bright on glass; a low-contrast rule when opaque.
    static func hairline(_ scheme: ColorScheme, opaque: Bool = false) -> Color {
        if opaque { return scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.10) }
        return scheme == .dark ? Color.white.opacity(0.20) : Color.white.opacity(0.78)
    }

    /// The milk veil's white, `rgba(255,255,255,.22)`. The blur that goes with it comes from the
    /// enhancer's plan, not from here — it is a function of the step, not a constant.
    static let veilWhite = Color.white

    // MARK: Geometry

    /// Concentric, outermost first. A radius that is not on this ladder is a mistake.
    enum Radius {
        static let screen: CGFloat = 48
        static let sheet: CGFloat = 38
        static let frame: CGFloat = 32
        /// Panels. The handoff's headline radius.
        static let card: CGFloat = 28
        static let plate: CGFloat = 22
        static let tile: CGFloat = 22
        static let swatch: CGFloat = 8
    }

    enum Space {
        static let hair: CGFloat = 4
        static let tight: CGFloat = 8
        static let gap: CGFloat = 12
        static let grid: CGFloat = 16
        static let margin: CGFloat = 20
        static let section: CGFloat = 32
    }

    /// Everything tappable. Not a suggestion — the handoff states it as a floor.
    static let minimumHitTarget: CGFloat = 44
    static let primaryCapsuleHeight: CGFloat = 56
    static let pillHeight: CGFloat = 44
    static let compactPillHeight: CGFloat = 38
    static let circleButton: CGFloat = 52

    /// The comparison handle: 38 pt of visible grip on a 56 pt target (`1j`).
    static let handleGrip: CGFloat = 38
    static let handleTarget: CGFloat = 56
    /// The divider line itself.
    static let handleLineWidth: CGFloat = 2

    /// The paired library tile's corner swatch: 34 pt, 1.5 pt white border (`1f`).
    static let swatchSize: CGFloat = 34
    static let swatchBorder: CGFloat = 1.5
}

// MARK: - Type

/// The bundle's type ramp. Sizes are points at the default Dynamic Type size; `stFont` scales them.
struct STTextStyle {
    let size: CGFloat
    let weight: Font.Weight
    /// What this scales against. Picking the right one matters: a caption that scaled like a title
    /// would overrun its plate at the largest accessibility sizes.
    let relativeTo: Font.TextStyle

    static let largeTitle  = STTextStyle(size: 34, weight: .bold, relativeTo: .largeTitle)
    static let screenTitle = STTextStyle(size: 28, weight: .bold, relativeTo: .title)
    static let cardHeading = STTextStyle(size: 21, weight: .semibold, relativeTo: .title3)
    static let button      = STTextStyle(size: 17, weight: .semibold, relativeTo: .body)
    static let body        = STTextStyle(size: 16, weight: .regular, relativeTo: .body)
    static let secondary   = STTextStyle(size: 15, weight: .regular, relativeTo: .subheadline)
    static let control     = STTextStyle(size: 15, weight: .medium, relativeTo: .subheadline)
    /// The strength readout — "Subtle · 35". Slightly heavier than a caption because it is the
    /// number the whole screen is about.
    static let readout     = STTextStyle(size: 14, weight: .semibold, relativeTo: .subheadline)
    static let caption     = STTextStyle(size: 13, weight: .regular, relativeTo: .caption)
    static let footnote    = STTextStyle(size: 12.5, weight: .regular, relativeTo: .caption)
    /// The ORIGINAL / ENHANCED corner captions (`1d`), which are tracked-out small caps in the
    /// design.
    static let splitCaption = STTextStyle(size: 11, weight: .semibold, relativeTo: .caption2)
}

/// Applies a token text style, scaled for Dynamic Type.
///
/// `Font.system(size:weight:)` does **not** scale — a screen built from it ignores the user's text
/// size entirely, which is the single most common accessibility failure in a hand-tokenised design.
/// `@ScaledMetric` is what makes fixed point sizes honour the setting.
private struct STFontModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let monospacedDigits: Bool

    init(_ style: STTextStyle, monospacedDigits: Bool) {
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
    /// - Parameter tabularNumbers: for anything that counts — "step 9 of 20", the strength readout,
    ///   a library count. Proportional digits make those labels shimmy as they change, which reads
    ///   as instability in exactly the places the app is asking to be trusted.
    func stFont(_ style: STTextStyle, tabularNumbers: Bool = false) -> some View {
        modifier(STFontModifier(style, monospacedDigits: tabularNumbers))
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
