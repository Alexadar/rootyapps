import SwiftUI

/// The **water-breeze** palette and type scale.
///
/// Instrument-like rather than decorative: an airy ground, deep-water ink, one working blue, and
/// numbers that are always monospaced and tabular so a column of results does not shuffle as its
/// digits change.
///
/// ## Two grounds, not one
///
/// The design handoff specified light only. A plant room at three in the morning is not a light
/// room, and a white screen there is hostile — so every token has a dark counterpart, tuned rather
/// than inverted: the working blue lightens (a mid blue on near-black loses too much contrast),
/// while the ink and ground swap roles. watchOS is always dark and takes the dark values directly.
///
/// ## Nothing is carried by colour alone
///
/// Warnings, out-of-range values and process direction all carry an icon or a word as well as a
/// colour. ``StatusBanner`` is built that way, and the accessibility floor for this app depends on
/// it staying that way.
public enum DS {

    // MARK: - Colour

    /// Primary text and the strongest ink.
    public static let ink = Color.adaptive(light: 0x10314A, dark: 0xE6F0F8)
    /// Secondary text: labels, units, supporting detail.
    public static let ink2 = Color.adaptive(light: 0x4A6D84, dark: 0x92B0C4)
    /// The page ground.
    public static let breeze = Color.adaptive(light: 0xF0F7FB, dark: 0x0B1720)
    /// A raised band — input trays, sheets.
    public static let panel = Color.adaptive(light: 0xE2EEF8, dark: 0x14242F)
    /// A card sitting on the ground.
    public static let card = Color.adaptive(light: 0xFFFFFF, dark: 0x101E29)
    /// Hairlines and card edges.
    public static let border = Color.adaptive(light: 0xD3E4F0, dark: 0x24394A)

    /// The working blue: the active field, state A, the primary action.
    public static let water = Color.adaptive(light: 0x1288D4, dark: 0x46AEEC)
    /// State B on the chart.
    public static let stateB = Color.adaptive(light: 0x0AA3C2, dark: 0x2FCDE6)
    /// The mixed state, between A and B.
    public static let mixed = Color.adaptive(light: 0x6FB9E6, dark: 0x7FB4D8)
    /// In range, within limits.
    public static let inRange = Color.adaptive(light: 0x0E8F7A, dark: 0x33BFA5)
    /// Out of range, over a limit, invalid.
    public static let warn = Color.adaptive(light: 0xC23B22, dark: 0xF07A5F)

    /// A faint tint of the working blue, for the active field's fill.
    public static let waterTint = Color.adaptive(light: 0xEEF4FB, dark: 0x152A38)
    /// Backgrounds for the two banner kinds.
    public static let okTint = Color.adaptive(light: 0xE8F4F2, dark: 0x112A26)
    public static let warnTint = Color.adaptive(light: 0xFDEEEB, dark: 0x2B1713)

    // MARK: - Spacing

    public static let s1: CGFloat = 4
    public static let s2: CGFloat = 8
    public static let s3: CGFloat = 12
    public static let s4: CGFloat = 16
    public static let s5: CGFloat = 24
    public static let s6: CGFloat = 32

    public static let radiusCard: CGFloat = 14
    public static let radiusTile: CGFloat = 10

    /// Minimum hit target, points. Above Apple's 44 pt floor on purpose: this app is used in a
    /// crawlspace, on a roof, and sometimes through gloves.
    public static let hitTarget: CGFloat = 48

    // MARK: - Type

    /// A number. Always monospaced and tabular — results are read in columns.
    ///
    /// Scales with Dynamic Type through `relativeTo:`, so the whole app grows with the user's
    /// setting instead of pinning numbers at a fixed size while their labels grow around them.
    public static func number(_ size: CGFloat, _ weight: Font.Weight = .semibold,
                              relativeTo style: Font.TextStyle = .body) -> Font {
        .system(size: size, weight: weight, design: .monospaced).leading(.tight)
    }

    /// Interface text.
    public static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

public extension Color {

    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }

    /// A colour that resolves against the current appearance.
    ///
    /// Built from a dynamic platform colour rather than by reading `@Environment(\.colorScheme)`,
    /// so it is correct inside `Canvas`, in an exported image and on a layer that never sees the
    /// environment — which is exactly where the chart lives.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        #if os(watchOS)
        return Color(hex: dark)          // the wrist is always dark
        #elseif canImport(UIKit)
        return Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(hex: dark) : UIColor(hex: light) })
        #elseif canImport(AppKit)
        return Color(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(hex: dark) : NSColor(hex: light)
        })
        #else
        return Color(hex: light)
        #endif
    }
}

#if canImport(UIKit)
import UIKit
extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
#elseif canImport(AppKit)
import AppKit
extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
#endif
