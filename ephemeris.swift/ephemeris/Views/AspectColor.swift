import SwiftUI
import EphemerisKit

/// UI color for each aspect type (kept out of the UI-free EphemerisKit core), keyed by name.
extension AspectType {
    /// Neon Nebula aspect palette.
    var color: Color {
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
