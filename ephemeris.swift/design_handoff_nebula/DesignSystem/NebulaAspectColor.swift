import SwiftUI
import EphemerisKit

/// Nebula aspect colours — vivid neon palette. Replaces the values in AspectColor.swift.
/// Keyed by aspect `name` so it stays out of the UI-free EphemerisKit core.
extension AspectType {
    var nebulaColor: Color {
        switch name {
        case "Conjunction": Color(rgbHex: 0xFF5A7A)   // hot pink
        case "Sextile":     Color(rgbHex: 0x35E7FF)   // cyan
        case "Square":      Color(rgbHex: 0xFFB020)   // amber
        case "Trine":       Color(rgbHex: 0x4DF0A0)   // aurora green
        case "Opposition":  Color(rgbHex: 0xC061FF)   // violet
        default:            Color(rgbHex: 0x9A93FF)
        }
    }
}

// In the chart wheel, draw each aspect chord twice for a neon glow:
//   1. wide, low-opacity  (lineWidth ≈ 5, opacity 0.2, round cap)   ← the halo
//   2. thin, full-opacity (lineWidth ≈ 1.6, round cap)             ← the core
//
//   ctx.stroke(chord, with: .color(a.type.nebulaColor.opacity(0.2)),
//              style: StrokeStyle(lineWidth: 5, lineCap: .round))
//   ctx.stroke(chord, with: .color(a.type.nebulaColor),
//              style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
