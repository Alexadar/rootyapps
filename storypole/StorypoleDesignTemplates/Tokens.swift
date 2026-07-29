import SwiftUI

/// Storypole design tokens — light and dark.
///
/// A tape is read in daylight AND in an attic with a headlamp, so every surface and ink token
/// carries both values. Nothing here pins a point size: every font goes through Dynamic Type.
///
/// Drop-in replacement for the previous `DesignShared/Tokens.swift`. Every symbol that existed
/// before still exists with the same name, so no call site changes.
public enum SP {

    // MARK: Surfaces
    /// The board. Warm paper by day, warm graphite by night — never clinical white, never pure black.
    public static let background  = Color(light: 0xF4F1EA, dark: 0x16140F)
    /// A card laid on the board.
    public static let surface     = Color(light: 0xFFFFFF, dark: 0x211E17)
    /// A well cut into a card: fields, chips, mark tiles.
    public static let surfaceSunk = Color(light: 0xEAE6DC, dark: 0x100E09)
    /// A pencil line, not a border. One hairline only; never two nested.
    public static let hairline    = Color(light: 0xD6D1C5, dark: 0x353026)

    // MARK: Ink
    public static let textPrimary   = Color(light: 0x1A1815, dark: 0xF5F2EA)
    public static let textSecondary = Color(light: 0x6A645A, dark: 0xA9A298)
    public static let textTertiary  = Color(light: 0x968F84, dark: 0x776F65)

    // MARK: Accent — the keel mark on the board
    public static let accent     = Color(light: 0xB93C09, dark: 0xF4763A)
    public static let accentSoft = Color(light: 0xFCE5D6, dark: 0x3A2014)
    public static let onAccent   = Color(light: 0xFFFFFF, dark: 0x14120D)

    // MARK: The tape itself
    /// The blade only. Yellow is reserved: it appears nowhere else in the app.
    public static let tapeBody   = Color(light: 0xF2C94C, dark: 0xD9B23C)
    public static let tapeBodyLo = Color(light: 0xE7B930, dark: 0xBE9829)
    public static let tapeEdge   = Color(light: 0xC79A1E, dark: 0x8E7018)
    public static let tapeMark   = Color(light: 0x1C1A17, dark: 0x14120D)
    public static let tapeHook   = Color(light: 0x3A342B, dark: 0x2A251E)
    public static let tapeCursor = Color(light: 0xB93C09, dark: 0xF4763A)

    // MARK: Radii
    public static let rCard: CGFloat = 20
    public static let rTile: CGFloat = 16
    public static let rChip: CGFloat = 10
    public static let rKey: CGFloat  = 14

    // MARK: Spacing — a 4 pt rhythm, named so layouts stay in step
    public static let s1: CGFloat = 4
    public static let s2: CGFloat = 8
    public static let s3: CGFloat = 12
    public static let s4: CGFloat = 16
    public static let s5: CGFloat = 24

    /// Minimum tap target. Never smaller, on any platform.
    public static let hit: CGFloat = 44
}

/// The type system. Two families and nothing else:
/// SF Pro for language, SF Mono for anything a tape can measure.
///
/// Every entry is a Dynamic Type text style, so all of it scales.
public enum SPType {
    /// The one big honest number.
    public static let readout   = Font.system(.largeTitle, design: .monospaced).weight(.semibold)
    /// A secondary measured value.
    public static let value     = Font.system(.title2, design: .monospaced).weight(.semibold)
    /// An inline measured value inside a row.
    public static let valueSm   = Font.system(.body, design: .monospaced).weight(.medium)
    /// A key cap.
    public static let key       = Font.system(.title3, design: .monospaced).weight(.medium)
    /// A mark in a mark list.
    public static let mark      = Font.system(.caption, design: .monospaced)
    /// A screen or card title.
    public static let title     = Font.headline
    /// A field or result label.
    public static let label     = Font.footnote
    /// A section eyebrow.
    public static let eyebrow   = Font.footnote.weight(.semibold)
    /// A citation, a caveat, a unit.
    public static let footnote  = Font.caption2
}

public extension Color {
    /// sRGB from `0xRRGGBB`.
    init(rgbHex v: UInt) {
        self.init(.sRGB,
                  red:   Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue:  Double(v & 0xFF) / 255,
                  opacity: 1)
    }

    /// One token, two appearances. watchOS resolves to `dark`, which is correct there.
    init(light: UInt, dark: UInt) {
#if os(watchOS)
        self.init(rgbHex: dark)
#elseif canImport(UIKit)
        self.init(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(Color(rgbHex: dark)) : UIColor(Color(rgbHex: light)) })
#else
        self.init(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(Color(rgbHex: dark)) : NSColor(Color(rgbHex: light))
        })
#endif
    }
}
