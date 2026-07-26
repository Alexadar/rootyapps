import SwiftUI

extension Color {
    /// Build a Color from a 0xRRGGBB integer.
    init(rgbHex: UInt) {
        self.init(.sRGB,
                  red: Double((rgbHex >> 16) & 0xFF) / 255,
                  green: Double((rgbHex >> 8) & 0xFF) / 255,
                  blue: Double(rgbHex & 0xFF) / 255,
                  opacity: 1)
    }
}
