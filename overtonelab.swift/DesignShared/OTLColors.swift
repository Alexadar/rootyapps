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

    /// Audio Analysis. A SOURCE accent, deliberately not one of the seven section accents: Measure is
    /// not an eighth section, and borrowing a section's colour would make it look like one. Provenance
    /// never relies on this — measured values are marked by glyph, texture and words, so the marking
    /// survives greyscale and colour blindness.
    static let measureAccent  = Color(rgbHex: 0x7FD1C1)

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
        case .timing:    return Color(rgbHex: 0x5B8DEF) // blue
        case .tuning:    return Color(rgbHex: 0xF2B84B) // amber
        case .acoustics: return Color(rgbHex: 0x43C8C0) // aqua
        case .signal:    return Color(rgbHex: 0x8B7BF0) // violet
        case .stereo:    return Color(rgbHex: 0x6FCF97) // green
        case .utility:   return Color(rgbHex: 0xE08AA0) // rose
        case .design:    return Color(rgbHex: 0xF0785A) // coral
        }
    }
}

extension Tool {
    /// Convenience: a tool inherits its section's accent.
    var accent: Color { section.accent }

    /// A short representative readout shown on the catalog tile, in the section accent.
    var sample: String {
        switch self {
        case .tempo: return "500 ms";     case .delay: return "250 ms"
        case .timecode: return "108000 fr"; case .pitch: return "A4 440 Hz"
        case .partch: return "702 ¢";     case .comma: return "12-EDO";     case .mersenne: return "82 N"
        case .sabine: return "0.8 s";     case .webster: return "500 Hz";   case .bernoulli: return "343 Hz"
        case .formant: return "500·1500"; case .spl: return "−6 dB / 2×"
        case .roommodes: return "34.3 Hz"; case .air: return "5 dB/km";     case .sbir: return "143 Hz"
        case .butterworth: return "−3 dB"; case .fletcher: return "A·C·Z";  case .benchmark: return "−14 LUFS"
        case .passive: return "159 Hz";   case .biquad: return "coeffs";    case .compressor: return "4:1"
        case .sra: return "96°"
        case .levels: return "+6 dB";     case .file: return "10.1 MB";     case .pan: return "−3 dB"
        case .thiele: return "47 L"
        }
    }
}
