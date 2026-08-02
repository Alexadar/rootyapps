import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// Marine Nav — watchOS design tokens.
//
// The wrist half of the "Chart Table" system. Presentation only: nothing here
// computes a physical quantity. Every number still arrives already-computed from
// TidesKit / GeomagKit / GeodesyKit / CelestialNavKit.
//
// Deliberate deviations from the phone/Mac system are marked ⚠ DEVIATION and
// explained in README.md.
// ─────────────────────────────────────────────────────────────────────────────

// MARK: - Mode

/// Same case names as the phone's `MarineMode`, on purpose: the two systems must
/// share vocabulary, and a mariner who set "Night · red" on the phone should find
/// the same words on the watch.
///
/// ⚠ DEVIATION — `.auto`. On iOS/macOS `.auto` follows the system light/dark
/// scheme. watchOS has no such setting, so there is nothing to follow: `.auto`
/// resolves to `.dark`. Resolving it by station-local twilight instead would need
/// a sunrise/sunset solver no Kit exposes, and computing one in a view is
/// forbidden — see README "Seams".
enum WatchMode: String, CaseIterable, Identifiable, Sendable {
    case auto, day, dark, nightDim, nightRed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:     return "Auto"
        case .day:      return "Day"
        case .dark:     return "Dusk"
        case .nightDim: return "Night · dim"
        case .nightRed: return "Night · red"
        }
    }

    var symbol: String {
        switch self {
        case .auto:     return "circle.lefthalf.filled"
        case .day:      return "sun.max"
        case .dark:     return "moon"
        case .nightDim: return "moon.stars"
        case .nightRed: return "moon.circle.fill"
        }
    }
}

// MARK: - Palette

/// ⚠ DEVIATION — the canvas is black in every mode.
///
/// The phone's Day palette is warm chart paper (#EAE6DC). On a wrist that is
/// wrong three times over: the always-on display must be dark, OLED black costs
/// no power, and a paper-white rectangle at full brightness ruins night vision
/// the moment you check the time. So on the watch, "Day" is not a paper theme —
/// it is a **sunlight profile**: pure-white ink, heavier weights, thicker
/// strokes, brighter accents. Dusk softens the ink; the two night stages carry
/// over unchanged in intent.
struct WatchPalette: Sendable {
    let canvas: Color
    /// Cards and the curve's plot ground. Only one step off canvas — heavy
    /// panels waste a small screen.
    let surface: Color
    let ink: Color
    let inkDim: Color
    let hairline: Color
    let water: Color
    let waterFillOpacity: Double
    let flood: Color
    let ebb: Color
    let caution: Color
    /// True when hue carries no information (night red). Rising/falling and
    /// flood/ebb must then read by GLYPH or POSITION only.
    let signByGlyph: Bool
    /// Sunlight profile: heavier weights and thicker strokes.
    let boldForGlare: Bool

    static let day = WatchPalette(
        canvas: .black, surface: Color(watchHex: 0x121A20),
        ink: .white, inkDim: Color(watchHex: 0xA9BCC7),
        hairline: Color.white.opacity(0.16),
        water: Color(watchHex: 0x6FD3EC), waterFillOpacity: 0.22,
        flood: Color(watchHex: 0x5FD8C6), ebb: Color(watchHex: 0xF0B15C),
        caution: Color(watchHex: 0xFF7F5F),
        signByGlyph: false, boldForGlare: true)

    static let dark = WatchPalette(
        canvas: .black, surface: Color(watchHex: 0x0E1720),
        ink: Color(watchHex: 0xEAF2F6), inkDim: Color(watchHex: 0x8CA3B0),
        hairline: Color.white.opacity(0.10),
        water: Color(watchHex: 0x58C4E0), waterFillOpacity: 0.16,
        flood: Color(watchHex: 0x4FC0B2), ebb: Color(watchHex: 0xE0A24E),
        caution: Color(watchHex: 0xE86A4E),
        signByGlyph: false, boldForGlare: false)

    static let nightDim = WatchPalette(
        canvas: .black, surface: Color(watchHex: 0x080D11),
        ink: Color(watchHex: 0xA8B8C2), inkDim: Color(watchHex: 0x64757F),
        hairline: Color(watchHex: 0xA8B8C2).opacity(0.10),
        water: Color(watchHex: 0x4A8C9E), waterFillOpacity: 0.14,
        flood: Color(watchHex: 0x3F8E86), ebb: Color(watchHex: 0x8A7350),
        caution: Color(watchHex: 0x9E5A44),
        signByGlyph: false, boldForGlare: false)

    static let nightRed = WatchPalette(
        canvas: .black, surface: Color(watchHex: 0x120303),
        ink: Color(watchHex: 0xFF7A63), inkDim: Color(watchHex: 0xA83A28),
        hairline: Color(watchHex: 0xFF5A3C).opacity(0.16),
        water: Color(watchHex: 0xFF5A3C), waterFillOpacity: 0.14,
        flood: Color(watchHex: 0xFF7A63), ebb: Color(watchHex: 0xFF7A63),
        caution: Color(watchHex: 0xFF9A85),
        signByGlyph: true, boldForGlare: false)

    var heroInk: Color { signByGlyph ? Color(watchHex: 0xFF9A85) : ink }

    /// Curve/rule weight. Thicker in glare, thinner at night.
    var stroke: CGFloat { boldForGlare ? 3 : 2.5 }
}

// MARK: - Theme

struct WatchTheme: Sendable {
    var mode: WatchMode = .auto
    /// Always-on (wrist-down) state. A DISTINCT visual state, not the same view
    /// faded: see `WatchTheme.dimmed` and every `isLuminanceReduced` branch.
    var luminanceReduced: Bool = false

    var palette: WatchPalette {
        switch mode {
        case .auto, .dark: return .dark
        case .day:         return .day
        case .nightDim:    return .nightDim
        case .nightRed:    return .nightRed
        }
    }

    var isNight: Bool { mode == .nightDim || mode == .nightRed }

    /// Always-on: pull ink back one step, drop every hairline, and stop drawing
    /// anything that reads as fine detail. Luminance, not opacity — a faded view
    /// still lights the same pixels.
    var dimmed: WatchTheme { var c = self; c.luminanceReduced = true; return c }

    /// Ink for the always-on state.
    var ambientInk: Color { luminanceReduced ? palette.inkDim : palette.ink }
    var ambientHero: Color { luminanceReduced ? palette.ink.opacity(0.75) : palette.heroInk }
    /// Hairlines and gridlines vanish when the display is dimmed — they smear.
    var ambientHairline: Color { luminanceReduced ? .clear : palette.hairline }
}

private struct WatchThemeKey: EnvironmentKey {
    static let defaultValue = WatchTheme()
}

extension EnvironmentValues {
    var watchTheme: WatchTheme {
        get { self[WatchThemeKey.self] }
        set { self[WatchThemeKey.self] = newValue }
    }
}

// MARK: - Size class
//
// Design fluidly, never to a model. Screens run from the 40 mm SE (162 pt wide)
// to the 49 mm Ultra (≈205 pt). We branch on measured width, not on device.

enum WatchSize: Sendable {
    /// ≤176 pt: 40 mm SE, 41 mm Series.
    case compact
    /// 177…199 pt: 42 mm / 44 mm / 45 mm.
    case regular
    /// ≥200 pt: 46 mm, 49 mm Ultra.
    case large

    static func measuring(_ width: CGFloat) -> WatchSize {
        if width <= 176 { return .compact }
        if width < 200 { return .regular }
        return .large
    }

    /// Hero numeral size. Deliberately conservative: it must survive the largest
    /// accessibility text size on the smallest screen, and `ViewThatFits` in
    /// `WatchHero` drops a rung further if it still does not fit.
    var hero: CGFloat {
        switch self {
        case .compact: return 34
        case .regular: return 40
        case .large:   return 46
        }
    }

    var gutter: CGFloat {
        switch self {
        case .compact: return 6
        case .regular: return 8
        case .large:   return 10
        }
    }

    /// Height of the inline curve.
    var curveHeight: CGFloat {
        switch self {
        case .compact: return 44
        case .regular: return 52
        case .large:   return 62
        }
    }
}

// MARK: - Type
//
// SF for words, monospaced digits for every value — the readout updates
// continuously and must not jitter. On the watch this matters more than
// anywhere else, so numerals additionally sit in FIXED-WIDTH SLOTS
// (`WatchSlot`), so a value changing from 9.9 to 10.0 does not shove its unit.

enum WatchType {
    static func hero(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }
    static let value = Font.system(size: 17, weight: .semibold, design: .monospaced)
    static let valueSmall = Font.system(size: 15, weight: .medium, design: .monospaced)
    static let mono13 = Font.system(size: 13, weight: .medium, design: .monospaced)
    static let mono11 = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let label = Font.system(size: 14)
    static let labelSmall = Font.system(size: 12)
    static let section = Font.system(size: 11, weight: .semibold)
    static let caption = Font.system(size: 11)
}

enum WatchMetrics {
    /// watchOS taps are a fingertip on a wet, moving wrist. Rows are 40 pt;
    /// anything consequential is 44 pt or more; MARK is a third of the screen.
    static let rowHeight: CGFloat = 40
    static let target: CGFloat = 44
    static let cardRadius: CGFloat = 10
    static let cardPadding: CGFloat = 8
    static let sectionGap: CGFloat = 10
}

/// A right-aligned fixed-width numeral slot. Prevents the layout shifting as a
/// value gains or loses a digit.
struct WatchSlot: View {
    let text: String
    var font: Font = WatchType.value
    var width: CGFloat
    var color: Color

    var body: some View {
        Text(text)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
            .frame(width: width, alignment: .trailing)
    }
}

// MARK: - Formatting

/// Same POSIX pin as the phone: navigational values are dot-separated in every
/// locale (a European locale once rendered `54,6`).
enum WatchFormat {
    static let posix = Locale(identifier: "en_US_POSIX")

    static func number(_ fraction: ClosedRange<Int> = 0...2) -> FloatingPointFormatStyle<Double> {
        .number.precision(.fractionLength(fraction)).locale(posix)
    }

    /// `HH:mm` in the STATION's zone. Never the watch's own zone — a tide time in
    /// the wrong zone is a navigational error.
    static func time(_ date: Date, zone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = posix
        f.timeZone = zone
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// `HH:mm:ss.SSS` — for a sight mark, where a second is a quarter of a mile.
    static func timeMillis(_ date: Date, zone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = posix
        f.timeZone = zone
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: date)
    }

    /// `2h 17m`. Coarsened to 5-minute granularity in the always-on state, where
    /// a per-second countdown would burn the display and cannot be read anyway.
    static func countdown(_ seconds: Int, coarse: Bool = false) -> String {
        let s = max(seconds, 0)
        if coarse {
            let m = (s / 60 / 5) * 5
            return m >= 60 ? String(format: "%dh %02dm", m / 60, m % 60) : "\(m)m"
        }
        return s >= 3600 ? String(format: "%dh %02dm", s / 3600, (s % 3600) / 60)
                         : String(format: "%dm", s / 60)
    }
}

// MARK: - Shared pieces

/// Screen chrome: title line + station + zone, then content. Every screen names
/// its station and its zone, always.
struct WatchScreen<Content: View>: View {
    @Environment(\.watchTheme) private var theme
    let title: String
    var stationName: String?
    var zone: String?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WatchMetrics.sectionGap) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title.uppercased())
                        .font(WatchType.section)
                        .tracking(0.8)
                        .foregroundStyle(theme.palette.inkDim)
                    if let stationName {
                        HStack(spacing: 4) {
                            Text(stationName)
                                .font(WatchType.label)
                                .foregroundStyle(theme.ambientInk)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            if let zone {
                                Text(zone)
                                    .font(WatchType.mono11)
                                    .foregroundStyle(theme.palette.inkDim)
                            }
                        }
                    }
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.palette.canvas)
    }
}

/// The one number a two-second glance lands on, with its trend told by GLYPH —
/// never by hue, because red mode has no hue to spare.
struct WatchHero: View {
    @Environment(\.watchTheme) private var theme
    let value: String
    let unit: String
    /// True = rising / flooding.
    let positive: Bool
    /// e.g. "0.82 ft/h"
    let rate: String
    let size: WatchSize
    /// Goes on the visible Text — never on a `.hidden()` view, which is removed
    /// from the accessibility tree.
    let identifier: String
    let voiceOver: String

    private var trendGlyph: String { positive ? "arrow.up" : "arrow.down" }
    private var trendColor: Color {
        theme.palette.signByGlyph ? theme.ambientInk
                                  : (positive ? theme.palette.flood : theme.palette.ebb)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ViewThatFits(in: .horizontal) {
                heroRow(size.hero)
                heroRow(size.hero - 6)
                heroRow(size.hero - 12)
            }
            HStack(spacing: 4) {
                Image(systemName: trendGlyph)
                    .font(.system(size: 11, weight: .bold))
                Text(positive ? "RISING" : "FALLING")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                Text(rate)
                    .font(WatchType.mono11)
                    .monospacedDigit()
            }
            .foregroundStyle(trendColor)
            .opacity(theme.luminanceReduced ? 0.75 : 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(voiceOver)
        .accessibilityIdentifier(identifier)
    }

    private func heroRow(_ pt: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(WatchType.hero(pt))
                .monospacedDigit()
                .foregroundStyle(theme.ambientHero)
            Text(unit)
                .font(.system(size: max(pt * 0.34, 12), weight: .medium))
                .foregroundStyle(theme.palette.inkDim)
        }
        .lineLimit(1)
    }
}

/// A compact card. Hairline only — no shadow, and no hairline at all when the
/// display is dimmed.
struct WatchCard<Content: View>: View {
    @Environment(\.watchTheme) private var theme
    var accent: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) { content }
            .padding(WatchMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.luminanceReduced ? .clear : theme.palette.surface,
                        in: RoundedRectangle(cornerRadius: WatchMetrics.cardRadius,
                                             style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: WatchMetrics.cardRadius, style: .continuous)
                .strokeBorder(accent?.opacity(0.4) ?? theme.ambientHairline, lineWidth: 1))
    }
}

/// The next turning point: kind, station-local clock time, countdown. Kind reads
/// by glyph so it survives red mode.
struct WatchNextTurn: View {
    @Environment(\.watchTheme) private var theme
    let kind: String
    let high: Bool
    let time: String
    let countdown: String
    let identifier: String
    let voiceOver: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: high ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.system(size: 10))
                .foregroundStyle(theme.palette.signByGlyph
                                 ? theme.ambientInk
                                 : (high ? theme.palette.water : theme.palette.ebb))
            Text(kind)
                .font(WatchType.labelSmall)
                .foregroundStyle(theme.palette.inkDim)
            Text(time)
                .font(WatchType.valueSmall)
                .monospacedDigit()
                .foregroundStyle(theme.ambientInk)
            Spacer(minLength: 2)
            Text(countdown)
                .font(WatchType.valueSmall)
                .monospacedDigit()
                .foregroundStyle(theme.ambientInk)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(voiceOver)
        .accessibilityIdentifier(identifier)
    }
}

/// Provenance, one line. On the watch it may live one scroll down — but it is
/// never absent, and it never becomes a chevron.
struct WatchProvenance: View {
    @Environment(\.watchTheme) private var theme
    let kit: String
    let authority: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("COMPUTED ON THIS DEVICE")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(theme.palette.inkDim)
            Text(kit)
                .font(WatchType.mono13)
                .foregroundStyle(theme.ambientInk)
            Text("Validated against \(authority). Offline · no subscription.")
                .font(WatchType.caption)
                .foregroundStyle(theme.palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A model caveat. Always visible, never behind a disclosure — same rule as the
/// phone. On the watch it is a bordered block at the foot of the screen.
struct WatchCaveat: View {
    @Environment(\.watchTheme) private var theme
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.palette.caution)
            Text(text)
                .font(WatchType.caption)
                .foregroundStyle(theme.palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(WatchMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: WatchMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.palette.caution.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Colour helper

extension Color {
    init(watchHex hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
