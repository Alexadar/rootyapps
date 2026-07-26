import SwiftUI

// TrueCourse — redesign colour & metric tokens. View layer only.
//
// Unlike a single static palette, TrueCourse is theme-aware: a "Dark" cockpit palette by
// day and a low-blue "Night" (red-shift) palette that preserves dark adaptation in the
// flight deck. Tokens are resolved from the environment palette (`@Environment(\.tc)`),
// so a single `.tcTheme(_:)` at the root recolours the whole app.
//
// `Color(rgbHex:)` matches the app's existing ColorHex helper. If the app doesn't already
// define it, keep the small extension at the bottom of this file.

// MARK: - Theme

enum TCTheme: String, CaseIterable, Identifiable {
    case dark          // default — matte glass-cockpit, sunlight-legible
    case night         // red-shift — preserves night vision
    var id: String { rawValue }
    var palette: TCPalette { self == .night ? .night : .dark }
}

// MARK: - Palette

/// All colour tokens for one theme. Read via `@Environment(\.tc)` in a View.
struct TCPalette {
    // Surfaces
    let background:    Color
    let grouped:       Color   // grouped-list backdrop
    let surface:       Color   // matte card / tile / segment track
    let surfaceRaised: Color   // the result / readout card & fields
    let pressed:       Color   // pressed / unit chip
    let hairline:      Color   // 1px card & segment stroke
    let chipFill:      Color   // NumberField value chip

    // Text
    let textPrimary:   Color   // values, tool names
    let textSecondary: Color   // labels
    let textTertiary:  Color   // units, chevrons

    // Brand + semantics (cockpit convention)
    let brand:         Color   // primary control / focus ring
    let onAccent:      Color   // ink on top of an accent fill
    let caution:       Color   // amber
    let warning:       Color   // red
    let normal:        Color   // green — "within limits"
    let star:          Color   // favourite star (filled)

    // The single source of wayfinding colour: one accent per calculator group, via
    // `accent(_:)` below. In `night`, accents collapse to a warm monochrome-red scale so
    // no cool light reaches the flight deck — the grouping survives, the blue does not.

    // MARK: Presets

    static let dark = TCPalette(
        background:    Color(rgbHex: 0x090C10),
        grouped:       Color(rgbHex: 0x0D1218),
        surface:       Color(rgbHex: 0x141B23),
        surfaceRaised: Color(rgbHex: 0x1A232D),
        pressed:       Color(rgbHex: 0x233040),
        hairline:      Color.white.opacity(0.08),
        chipFill:      Color.white.opacity(0.06),
        textPrimary:   Color(rgbHex: 0xEAEFF4),
        textSecondary: Color(rgbHex: 0x95A2B1),
        textTertiary:  Color(rgbHex: 0x616D7B),
        brand:         Color(rgbHex: 0x39C6DC),
        onAccent:      Color(rgbHex: 0x04212A),
        caution:       Color(rgbHex: 0xF2B441),
        warning:       Color(rgbHex: 0xFF5D5D),
        normal:        Color(rgbHex: 0x45D18A),
        star:          Color(rgbHex: 0xF2B441),
        accentMap: [
            .wind:      Color(rgbHex: 0x35C4DE),
            .airspeed:  Color(rgbHex: 0x47D18A),
            .altitude:  Color(rgbHex: 0x5B9BFF),
            .nav:       Color(rgbHex: 0xE766C8),
            .fuel:      Color(rgbHex: 0xF2A93E),
            .climb:     Color(rgbHex: 0x8E8CFF),
            .weightBal: Color(rgbHex: 0xFF8A5B),
            .convert:   Color(rgbHex: 0x8B98A9),
        ])

    static let night = TCPalette(
        background:    Color(rgbHex: 0x0A0304),
        grouped:       Color(rgbHex: 0x0E0405),
        surface:       Color(rgbHex: 0x190708),
        surfaceRaised: Color(rgbHex: 0x210A0B),
        pressed:       Color(rgbHex: 0x2C0F10),
        hairline:      Color(rgbHex: 0xFF6040).opacity(0.16),
        chipFill:      Color(rgbHex: 0xFF6040).opacity(0.10),
        textPrimary:   Color(rgbHex: 0xFF6A52),
        textSecondary: Color(rgbHex: 0xC4503C),
        textTertiary:  Color(rgbHex: 0x7E3226),
        brand:         Color(rgbHex: 0xFF7A5E),
        onAccent:      Color(rgbHex: 0x1B0603),
        caution:       Color(rgbHex: 0xFF8A4C),
        warning:       Color(rgbHex: 0xFF5236),
        normal:        Color(rgbHex: 0xFF9B6E),
        star:          Color(rgbHex: 0xFF9C5C),
        accentMap: [
            .wind:      Color(rgbHex: 0xFF7B5E),
            .airspeed:  Color(rgbHex: 0xFF8A66),
            .altitude:  Color(rgbHex: 0xFF6F52),
            .nav:       Color(rgbHex: 0xFF6048),
            .fuel:      Color(rgbHex: 0xFF9C5C),
            .climb:     Color(rgbHex: 0xFF7355),
            .weightBal: Color(rgbHex: 0xFF6A4C),
            .convert:   Color(rgbHex: 0xC85A44),
        ])

    // Storage for the accent map; `accent(_:)` reads it.
    private let accentMap: [CalcSection: Color]
    private init(background: Color, grouped: Color, surface: Color, surfaceRaised: Color,
                 pressed: Color, hairline: Color, chipFill: Color, textPrimary: Color,
                 textSecondary: Color, textTertiary: Color, brand: Color, onAccent: Color,
                 caution: Color, warning: Color, normal: Color, star: Color,
                 accentMap: [CalcSection: Color]) {
        self.background = background; self.grouped = grouped; self.surface = surface
        self.surfaceRaised = surfaceRaised; self.pressed = pressed; self.hairline = hairline
        self.chipFill = chipFill; self.textPrimary = textPrimary
        self.textSecondary = textSecondary; self.textTertiary = textTertiary
        self.brand = brand; self.onAccent = onAccent; self.caution = caution
        self.warning = warning; self.normal = normal; self.star = star
        self.accentMap = accentMap
    }
}

extension TCPalette {
    func accent(_ s: CalcSection) -> Color { accentMap[s] ?? brand }
}

// MARK: - Metrics (theme-independent)

enum TC {
    static let rCard: CGFloat    = 18
    static let rTile: CGFloat    = 14
    static let rField: CGFloat   = 12
    static let rChip: CGFloat    = 8
    static let rSegment: CGFloat = 12

    static let cardPadding: CGFloat   = 16
    static let screenMargin: CGFloat  = 16
    static let gridGap: CGFloat       = 11
    static let minHit: CGFloat        = 44   // glove-sized targets
}

// MARK: - Calculator groups + accents

/// The eight calculator families. Each owns one accent — the wayfinding system.
enum CalcSection: String, CaseIterable, Identifiable, Hashable {
    case wind      = "Wind"
    case airspeed  = "Airspeed"
    case altitude  = "Altitude"
    case nav       = "Nav"
    case fuel      = "Fuel"
    case climb     = "Climb / Descent"
    case weightBal = "Weight & Balance"
    case convert   = "Convert"
    var id: String { rawValue }
}

extension Calculator {
    /// A calculator inherits its section's accent (resolve against the current palette).
    func accent(_ p: TCPalette) -> Color { p.accent(section) }
}

// MARK: - Environment plumbing

private struct TCPaletteKey: EnvironmentKey {
    static let defaultValue: TCPalette = .dark
}
extension EnvironmentValues {
    /// The active TrueCourse palette. Read as `@Environment(\.tc) private var tc`.
    var tc: TCPalette {
        get { self[TCPaletteKey.self] }
        set { self[TCPaletteKey.self] = newValue }
    }
}

extension View {
    /// Apply a TrueCourse theme to a subtree. Set once at the app root.
    func tcTheme(_ theme: TCTheme) -> some View {
        environment(\.tc, theme.palette)
            .preferredColorScheme(.dark)   // both palettes are dark-on-dark
    }
}

// MARK: - Hex helper (remove if the app already defines Color(rgbHex:))

extension Color {
    init(rgbHex: UInt32) {
        self.init(.sRGB,
                  red:   Double((rgbHex >> 16) & 0xFF) / 255,
                  green: Double((rgbHex >> 8)  & 0xFF) / 255,
                  blue:  Double(rgbHex & 0xFF) / 255,
                  opacity: 1)
    }
}
