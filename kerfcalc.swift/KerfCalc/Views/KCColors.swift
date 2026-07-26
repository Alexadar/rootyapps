import SwiftUI

// KERF — redesign colour & metric tokens. View layer only.
// Uses the app's existing Color(rgbHex:) helper (ColorHex.swift).
//
// Identity: a *light field instrument*. Warm concrete "paper" body, one dark
// graphite readout, a single hi-vis signal accent. Sunlight-readable and glove-first.
//
// Two colour jobs, kept separate:
//   • Wayfinding  → the trade accents (ToolSection.accent). Readable on light cards.
//   • The hero    → the one big number per screen, in `signal` on the dark instrument.

enum KC {
    // Surfaces — light "paper" body
    static let background     = Color(rgbHex: 0xEDE9E0)   // full-bleed app background
    static let surface        = Color(rgbHex: 0xFFFFFF)   // matte card / tile
    static let surfaceRaised  = Color(rgbHex: 0xF6F3EC)   // subtly raised card
    static let instrument     = Color(rgbHex: 0x16171B)   // dark readout / hero / formula card
    static let hairline       = Color.black.opacity(0.06) // 1px card & tile stroke
    static let chipFill        = Color(rgbHex: 0xF1EDE4)   // value / sample chip

    // Text on light
    static let textPrimary    = Color(rgbHex: 0x16171B)   // values, tool names
    static let textSecondary  = Color(rgbHex: 0x6E6F75)   // labels
    static let textTertiary   = Color(rgbHex: 0xA7A296)   // units, chevrons

    // Text on the dark instrument
    static let onInstrument   = Color(rgbHex: 0xF3F2EC)
    static let instrumentDim  = Color(rgbHex: 0x7C7D83)

    // Accents
    static let signal         = Color(rgbHex: 0xE8FB4A)   // hi-vis primary — "=" key, hero number, active
    static let star           = Color(rgbHex: 0xE8FB4A)   // favourite star (filled)
    static let ok             = Color(rgbHex: 0x2E9E67)
    static let warn           = Color(rgbHex: 0xD0603F)

    // Ink sitting on top of the signal fill (the "=" key, badges)
    static let onAccent       = Color(rgbHex: 0x101114)

    // Radii
    static let rCard: CGFloat    = 20
    static let rTile: CGFloat    = 19
    static let rChip: CGFloat    = 8
    static let rSegment: CGFloat = 12
    static let rKey: CGFloat     = 17
    static let rInput: CGFloat   = 11
}

extension ToolSection {
    /// Trade accent — the single source of wayfinding colour.
    var accent: Color {
        switch self {
        case .framing:   return Color(rgbHex: 0x2E6BFF) // blue
        case .concrete:  return Color(rgbHex: 0x7C8698) // slate
        case .takeoff:   return Color(rgbHex: 0x12B5A5) // teal
        case .materials: return Color(rgbHex: 0xF0785A) // coral
        case .convert:   return Color(rgbHex: 0xD99A2B) // ochre
        }
    }
    /// 13%-alpha wash of the accent — the tile code-badge fill.
    var tint: Color { accent.opacity(0.13) }
}

extension Tool {
    /// A tool inherits its section's accent.
    var accent: Color { section.accent }
    var tint: Color { section.tint }

    /// Short monospaced code shown on the redesign's catalog tiles.
    var code: String {
        switch self {
        case .rafter:    return "RAF"
        case .stairs:    return "STR"
        case .pitch:     return "ANG"
        case .concrete:  return "CNC"
        case .footing:   return "FTG"
        case .rebar:     return "RB#"
        case .aggregate: return "AGG"
        case .pavers:    return "PVR"
        case .area:      return "A□"
        case .volume:    return "VOL"
        case .roofing:   return "RF"
        case .estimate:  return "EST"
        case .miter:     return "MIT"
        case .lumber:    return "BF"
        case .mortar:    return "MOR"
        case .units:     return "CNV"
        }
    }
}
