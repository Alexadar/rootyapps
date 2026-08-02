import SwiftUI

/// Nebula design-system palette for Ephemeris Sky.
///
/// A vivid, immersive "deep-space" redesign of the app. All screens are dark;
/// cards are translucent glass with a soft violet border/glow, and the accent
/// language is a magenta→cyan spectrum with a vivid aspect palette.
///
/// Relies on `Color(rgbHex:)` from ColorHex.swift.
enum NebulaPalette {

    // MARK: Accent spectrum
    static let accent      = Color(rgbHex: 0xFF4D9D)   // magenta — primary accent (tint)
    static let accentCyan  = Color(rgbHex: 0x35E7FF)   // cyan — secondary accent
    static let accentViolet = Color(rgbHex: 0xC061FF)  // violet — tertiary
    static let accentGreen = Color(rgbHex: 0x4DF0A0)   // aurora green

    /// App-wide `.tint(...)` value. Also set AccentColor.colorset to 0xFF4D9D.
    static let tint = accent

    /// Wordmark / hero gradient (magenta → cyan).
    static let wordmark = LinearGradient(
        colors: [accent, accentCyan],
        startPoint: .leading, endPoint: .trailing)

    // MARK: Zodiac sign chip
    static let sign      = Color(rgbHex: 0x9D4EDD)     // solid chip fill
    static let signGlyph = Color.white                 // glyph on chip

    // MARK: Surfaces / text (dark glass)
    static let cardFill    = Color.white.opacity(0.055)
    static let cardFillAlt  = Color.white.opacity(0.075)  // Events card (denser)
    static let cardBorder  = Color(rgbHex: 0xB496FF).opacity(0.28)
    static let divider     = Color(rgbHex: 0xB496FF).opacity(0.14)

    static let textPrimary   = Color(rgbHex: 0xECE6FF)
    static let textSecondary = Color(rgbHex: 0xC8B9EB).opacity(0.85)   // ~rgba(200,185,235,0.62) over dark
    static let textHead      = Color(rgbHex: 0xBEAAEB).opacity(0.9)    // uppercase card headers
    static let textFaint     = Color(rgbHex: 0xBEAAEB).opacity(0.55)

    /// Planet glyphs on the wheel / rows (with a soft glow — see NebulaGlass).
    static let glyph = Color(rgbHex: 0xF2ECFF)
    /// Chart wheel rings + spokes.
    static let ring  = Color(rgbHex: 0x966EFF).opacity(0.42)

    // MARK: Status
    static let retrograde = Color(rgbHex: 0xE67E22)    // ℞ marker

    // MARK: Background
    static let bgTop    = Color(rgbHex: 0x0C0525)
    static let bgBottom = Color(rgbHex: 0x10082E)
    static let glowMagenta = Color(rgbHex: 0x3A0E6B)
    static let glowCyan    = Color(rgbHex: 0x0E3A6B)
}
