import SwiftUI
import EphemerisKit

/// UI color for each aspect type (kept out of the UI-free EphemerisKit core), keyed by name.
extension AspectType {
    var color: Color {
        switch name {
        case "Conjunction": Color(rgbHex: 0xe74c3c)
        case "Sextile":     Color(rgbHex: 0x3498db)
        case "Square":      Color(rgbHex: 0xe67e22)
        case "Trine":       Color(rgbHex: 0x2ecc71)
        case "Opposition":  Color(rgbHex: 0x9b59b6)
        default:            Color(rgbHex: 0x8b93a3)
        }
    }
}
