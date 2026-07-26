import SwiftUI

// Aurora HUD — colour & metric tokens. View layer only.
//
// Theme-aware: a "Dark" broadcast-HUD palette by default and a low-blue "Night"
// (red-shift) palette that preserves dark adaptation for aurora chasers in the field.
// Tokens resolve from the environment palette (`@Environment(\.sw)`), so a single
// `.swTheme(_:)` at the root recolours the whole app.
//
// Uses the app's existing `Color(hex:)` helper (DesignSystem/ColorHex.swift).

// MARK: - Theme

enum SWThemeChoice: String, CaseIterable, Identifiable {
    case dark          // default — matte broadcast HUD
    case night         // red-shift — preserves night vision under the aurora
    var id: String { rawValue }
    var palette: SWPalette { self == .night ? .night : .dark }
}

// MARK: - Sides (the matchup — the only thematic colour)

/// Every panel belongs to one side of the matchup the app reports: the Sun acting,
/// the Earth responding, and the solar wind linking them. One accent per side is the
/// entire wayfinding system.
enum SWSide: String, CaseIterable, Identifiable, Hashable {
    case solar = "Sun"          // flares & X-ray, solar activity, radio (R)
    case terra = "Earth"        // Kp, Hp30, aurora, geomagnetic (G)
    case link  = "Solar Wind"   // the neutral connector
    var id: String { rawValue }
}

// MARK: - Palette

/// All colour tokens for one theme. Read via `@Environment(\.sw)` in a View.
struct SWPalette {
    // Surfaces
    let background:    Color
    let grouped:       Color   // chart / grouped backdrop
    let surface:       Color   // matte card / tile / segment track
    let surfaceRaised: Color   // hero panel & fields
    let pressed:       Color   // chips / pressed
    let hairline:      Color   // 1px card & segment stroke
    let chipFill:      Color   // value chips

    // Text
    let textPrimary:   Color   // values, panel titles (soft, never #FFF)
    let textSecondary: Color   // labels, meaning lines
    let textTertiary:  Color   // units, sources, hints

    // Brand + semantics
    let brand:         Color   // aurora mint — primary control, focus, Hp30 hero
    let onAccent:      Color   // ink on top of an accent fill
    let normal:        Color   // severity 0 — quiet
    let caution:       Color   // severity 1–2 — storm in play
    let warning:       Color   // severity 3–5 — strong and above

    // MARK: Presets

    static let dark = SWPalette(
        background:    Color(hex: 0x080B14),
        grouped:       Color(hex: 0x0C111B),
        surface:       Color(hex: 0x111826),
        surfaceRaised: Color(hex: 0x17202F),
        pressed:       Color(hex: 0x202B3D),
        hairline:      Color.white.opacity(0.08),
        chipFill:      Color.white.opacity(0.06),
        textPrimary:   Color(hex: 0xE8EEF6),
        textSecondary: Color(hex: 0x93A1B4),
        textTertiary:  Color(hex: 0x5E6B7E),
        brand:         Color(hex: 0x4DF0A0),
        onAccent:      Color(hex: 0x04150C),
        normal:        Color(hex: 0x45D18A),
        caution:       Color(hex: 0xF2B441),
        warning:       Color(hex: 0xFF5D5D),
        sideMap: [
            .solar: Color(hex: 0xFF8A3D),
            .terra: Color(hex: 0x4DF0A0),
            .link:  Color(hex: 0x8B98A9),
        ])

    static let night = SWPalette(
        background:    Color(hex: 0x0A0304),
        grouped:       Color(hex: 0x0E0405),
        surface:       Color(hex: 0x190708),
        surfaceRaised: Color(hex: 0x210A0B),
        pressed:       Color(hex: 0x2C0F10),
        hairline:      Color(hex: 0xFF6040).opacity(0.16),
        chipFill:      Color(hex: 0xFF6040).opacity(0.10),
        textPrimary:   Color(hex: 0xFF6A52),
        textSecondary: Color(hex: 0xC4503C),
        textTertiary:  Color(hex: 0x7E3226),
        brand:         Color(hex: 0xFF7A5E),
        onAccent:      Color(hex: 0x1B0603),
        normal:        Color(hex: 0xFF9B6E),
        caution:       Color(hex: 0xFF8A4C),
        warning:       Color(hex: 0xFF5236),
        sideMap: [
            .solar: Color(hex: 0xFF7B52),
            .terra: Color(hex: 0xFF9B6E),
            .link:  Color(hex: 0xC85A44),
        ])

    // Storage for the side map; `side(_:)` reads it.
    private let sideMap: [SWSide: Color]
    private init(background: Color, grouped: Color, surface: Color, surfaceRaised: Color,
                 pressed: Color, hairline: Color, chipFill: Color, textPrimary: Color,
                 textSecondary: Color, textTertiary: Color, brand: Color, onAccent: Color,
                 normal: Color, caution: Color, warning: Color, sideMap: [SWSide: Color]) {
        self.background = background; self.grouped = grouped; self.surface = surface
        self.surfaceRaised = surfaceRaised; self.pressed = pressed; self.hairline = hairline
        self.chipFill = chipFill; self.textPrimary = textPrimary
        self.textSecondary = textSecondary; self.textTertiary = textTertiary
        self.brand = brand; self.onAccent = onAccent
        self.normal = normal; self.caution = caution; self.warning = warning
        self.sideMap = sideMap
    }
}

extension SWPalette {
    /// The matchup accent for a side.
    func side(_ s: SWSide) -> Color { sideMap[s] ?? brand }

    /// NOAA level 0…5 collapsed to the restrained 3-step ramp.
    /// The level *number* ("G3") carries precision; the colour carries urgency.
    func severity(_ level: Int) -> Color {
        switch level {
        case ..<1:  return normal
        case 1, 2:  return caution
        default:    return warning
        }
    }

    /// Flare class letter → severity (A/B/C quiet, M caution, X warning).
    func severity(flareClass: String) -> Color {
        switch flareClass.first {
        case "X":       return warning
        case "M":       return caution
        default:        return normal
        }
    }
}

// MARK: - Metrics (theme-independent)

enum SWM {
    static let chamfer: CGFloat  = 12   // 45° cut, top-trailing corner — the identity
    static let rCard: CGFloat    = 6
    static let rTile: CGFloat    = 5
    static let rField: CGFloat   = 6
    static let rChip: CGFloat    = 3
    static let rSegment: CGFloat = 6

    static let cardPadding: CGFloat  = 14
    static let screenMargin: CGFloat = 16
    static let gridGap: CGFloat      = 10
    static let minHit: CGFloat       = 44   // outdoors, at night, cold fingers
}

// MARK: - Environment plumbing

private struct SWPaletteKey: EnvironmentKey {
    static let defaultValue: SWPalette = .dark
}
extension EnvironmentValues {
    /// The active Aurora HUD palette. Read as `@Environment(\.sw) private var sw`.
    var sw: SWPalette {
        get { self[SWPaletteKey.self] }
        set { self[SWPaletteKey.self] = newValue }
    }
}

extension View {
    /// Apply an Aurora HUD theme to a subtree. Set once at the app root.
    func swTheme(_ theme: SWThemeChoice) -> some View {
        environment(\.sw, theme.palette)
            .preferredColorScheme(.dark)   // both palettes are dark-on-dark
    }
}

// MARK: - Compatibility bridge (old static `SW` tokens)
//
// Un-migrated call sites (e.g. `SW.cyan` in DashboardView) keep compiling AND land on the
// restrained system: the old per-metric hues collapse onto sides / severity / brand.
// These are static (dark-palette) values — migrate call sites to `@Environment(\.sw)`
// to pick up the Night theme, then delete this bridge.

enum SW {
    static let aurora   = SWPalette.dark.brand                    // brand mint
    static let magenta  = SWPalette.dark.warning                  // was storm/alert
    static let cyan     = SWPalette.dark.side(.link)              // was solar wind
    static let violet   = SWPalette.dark.brand                    // was geomagnetic (Hp30 hero)
    static let amber    = SWPalette.dark.caution                  // was flare/caution

    static let tint = aurora

    static let cardFill   = SWPalette.dark.surface
    static let cardFillHi = SWPalette.dark.surfaceRaised
    static let cardBorder = SWPalette.dark.hairline
    static let divider    = Color.white.opacity(0.06)

    static let textPrimary   = SWPalette.dark.textPrimary
    static let textSecondary = SWPalette.dark.textSecondary
    static let textHead      = SWPalette.dark.textSecondary
    static let textFaint     = SWPalette.dark.textTertiary

    static let bgTop    = SWPalette.dark.background
    static let bgBottom = SWPalette.dark.background   // flat — no gradient wash

    /// Old 6-colour NOAA band → restrained severity ramp.
    static func scaleColor(_ level: Int) -> Color { SWPalette.dark.severity(level) }
}
