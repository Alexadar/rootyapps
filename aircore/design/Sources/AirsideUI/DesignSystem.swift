import SwiftUI

/// Airside "water breeze" design system. Instrument-like: airy sky-blue ground,
/// deep-water ink, one working blue. Numbers are always monospaced + tabular.
public enum DS {
    // Colour — role first
    public static let ink      = Color(hex: 0x10314A)
    public static let ink2     = Color(hex: 0x4A6D84)
    public static let breeze   = Color(hex: 0xF0F7FB)   // background
    public static let panel    = Color(hex: 0xE2EEF8)
    public static let card     = Color.white
    public static let border   = Color(hex: 0xD3E4F0)
    public static let water    = Color(hex: 0x1288D4)   // work / state A
    public static let stateB   = Color(hex: 0x0AA3C2)
    public static let mixed    = Color(hex: 0x6FB9E6)
    public static let inRange  = Color(hex: 0x0E8F7A)
    public static let warn     = Color(hex: 0xC23B22)

    // Spacing scale
    public static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12
    public static let s4: CGFloat = 16, s5: CGFloat = 24, s6: CGFloat = 32
    public static let radiusCard: CGFloat = 14
    public static let hitTarget: CGFloat = 48   // above Apple's 44 floor, for gloves

    // Type — Instrument Sans for UI, IBM Plex Mono (or SF Mono fallback) for numbers.
    public static func number(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    public static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

public extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue:  Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// A tabular numeric readout with an attached, greyed unit.
public struct NumberReadout: View {
    let value: String, unit: String, size: CGFloat
    public init(_ value: String, unit: String, size: CGFloat = 26) {
        self.value = value; self.unit = unit; self.size = size
    }
    public var body: some View {
        (Text(value).font(DS.number(size)).foregroundColor(DS.ink)
         + Text(" \(unit)").font(DS.number(size * 0.5)).foregroundColor(DS.ink2))
            .monospacedDigit()
    }
}
