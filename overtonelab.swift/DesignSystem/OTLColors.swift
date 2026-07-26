import SwiftUI

// Overtone Lab — redesign colour & metric tokens. View layer only.
// Uses the app's existing Color(rgbHex:) helper (ColorHex.swift).

enum OTL {
    // Surfaces
    static let background     = Color(rgbHex: 0x08080B)   // was the violet gradient
    static let surface        = Color(rgbHex: 0x141419)   // matte card / tile / segment track
    static let surfaceRaised  = Color(rgbHex: 0x16161D)   // the result / readout card
    static let hairline       = Color.white.opacity(0.06) // 1px card & segment stroke
    static let chipFill        = Color.white.opacity(0.05) // NumberField value chip

    // Text
    static let textPrimary    = Color(rgbHex: 0xF5F5F7)
    static let textSecondary  = Color(rgbHex: 0x9A9AA6)
    static let textTertiary   = Color.white.opacity(0.30)

    // Favourite star (filled)
    static let star           = Color(rgbHex: 0xF2C14E)

    // Radii
    static let rCard: CGFloat    = 20
    static let rTile: CGFloat    = 16
    static let rChip: CGFloat    = 8
    static let rSegment: CGFloat = 12

    // Ink for text sitting on top of an accent fill (selected pill, badge)
    static let onAccent       = Color(rgbHex: 0x0A0A0C)
}

extension ToolSection {
    /// Section accent — the single source of wayfinding colour.
    var accent: Color {
        switch self {
        case .tuning:    return Color(rgbHex: 0xF2B84B) // amber
        case .acoustics: return Color(rgbHex: 0x43C8C0) // aqua
        case .signal:    return Color(rgbHex: 0x8B7BF0) // violet
        case .design:    return Color(rgbHex: 0xF0785A) // coral
        }
    }
}

extension Tool {
    /// Convenience: a tool inherits its section's accent.
    var accent: Color { section.accent }
}
