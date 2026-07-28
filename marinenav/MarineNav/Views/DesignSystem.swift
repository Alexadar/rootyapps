import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// Marine Nav — "Chart Table" design system.
//
// Presentation only. NOTHING in this file computes a predicted value: colour,
// type, spacing, surfaces and the chart treatment. All numbers still arrive
// already-computed from TidesKit / GeomagKit / GeodesyKit / CelestialNavKit.
//
// Four appearances, because this app is read at a helm:
//   .day       warm chart paper, maximum contrast in glare
//   .dark      ink-black at sea
//   .nightDim  stage 1 red-shift: no white light, desaturated
//   .nightRed  stage 2 red-shift: single hue, dark-adaptation safe
// ─────────────────────────────────────────────────────────────────────────────

// MARK: - Mode

enum MarineMode: String, CaseIterable, Identifiable, Sendable {
    case auto, day, dark, nightDim, nightRed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:     return "Auto"
        case .day:      return "Day"
        case .dark:     return "Dark"
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

struct MarinePalette: Sendable {
    let canvas: Color
    let surface: Color
    /// Sidebar / secondary chrome, one step off `canvas`.
    let chrome: Color
    let ink: Color
    let inkDim: Color
    let hairline: Color
    /// The water: the tide curve, links, the selected control.
    let water: Color
    let waterFillOpacity: Double
    let flood: Color
    let ebb: Color
    let caution: Color
    /// True when hue is not available as a signal (night red): rising/falling and
    /// flood/ebb must then be distinguished by glyph, never by colour.
    let signByGlyph: Bool
    /// Status-bar / keyboard appearance.
    let colorScheme: ColorScheme

    static let day = MarinePalette(
        canvas: Color(hex: 0xEAE6DC), surface: Color(hex: 0xFDFCF8), chrome: Color(hex: 0xE3DED1),
        ink: Color(hex: 0x10222E), inkDim: Color(hex: 0x5C6B75),
        hairline: Color(hex: 0x10222E).opacity(0.12),
        water: Color(hex: 0x0E5A78), waterFillOpacity: 0.13,
        flood: Color(hex: 0x0F7B8A), ebb: Color(hex: 0xA85A16), caution: Color(hex: 0xB3341C),
        signByGlyph: false, colorScheme: .light)

    static let dark = MarinePalette(
        canvas: Color(hex: 0x0A1218), surface: Color(hex: 0x131F27), chrome: Color(hex: 0x0F1A22),
        ink: Color(hex: 0xEAF2F6), inkDim: Color(hex: 0x8CA3B0),
        hairline: Color.white.opacity(0.10),
        water: Color(hex: 0x58C4E0), waterFillOpacity: 0.16,
        flood: Color(hex: 0x4FC0B2), ebb: Color(hex: 0xE0A24E), caution: Color(hex: 0xE86A4E),
        signByGlyph: false, colorScheme: .dark)

    static let nightDim = MarinePalette(
        canvas: Color(hex: 0x05080A), surface: Color(hex: 0x0B1014), chrome: Color(hex: 0x080C0F),
        ink: Color(hex: 0xA8B8C2), inkDim: Color(hex: 0x64757F),
        hairline: Color(hex: 0xA8B8C2).opacity(0.10),
        water: Color(hex: 0x4A8C9E), waterFillOpacity: 0.14,
        flood: Color(hex: 0x3F8E86), ebb: Color(hex: 0x8A7350), caution: Color(hex: 0x9E5A44),
        signByGlyph: false, colorScheme: .dark)

    static let nightRed = MarinePalette(
        canvas: Color(hex: 0x070101), surface: Color(hex: 0x150404), chrome: Color(hex: 0x0C0202),
        ink: Color(hex: 0xFF7A63), inkDim: Color(hex: 0xA83A28),
        hairline: Color(hex: 0xFF5A3C).opacity(0.16),
        water: Color(hex: 0xFF5A3C), waterFillOpacity: 0.14,
        flood: Color(hex: 0xFF7A63), ebb: Color(hex: 0xFF7A63), caution: Color(hex: 0xFF9A85),
        signByGlyph: true, colorScheme: .dark)

    /// Hero numerals sit one step brighter than body ink in the night palettes.
    var heroInk: Color {
        signByGlyph ? Color(hex: 0xFF9A85) : ink
    }
}

// MARK: - Theme

struct MarineTheme: Sendable {
    var mode: MarineMode = .auto
    var systemScheme: ColorScheme = .light

    var palette: MarinePalette {
        switch mode {
        case .auto:     return systemScheme == .dark ? .dark : .day
        case .day:      return .day
        case .dark:     return .dark
        case .nightDim: return .nightDim
        case .nightRed: return .nightRed
        }
    }

    var isNight: Bool { mode == .nightDim || mode == .nightRed }
}

private struct MarineThemeKey: EnvironmentKey {
    static let defaultValue = MarineTheme()
}

extension EnvironmentValues {
    var marine: MarineTheme {
        get { self[MarineThemeKey.self] }
        set { self[MarineThemeKey.self] = newValue }
    }
}

// MARK: - Metrics

enum MarineMetrics {
    static let gutter: CGFloat = 14        // card inset from the screen edge
    static let cardPadding: CGFloat = 14
    static let cardRadius: CGFloat = 14
    static let controlRadius: CGFloat = 10
    static let sectionGap: CGFloat = 18
    static let rowHeight: CGFloat = 46     // any row
    static let controlHeight: CGFloat = 52 // anything a wet hand must hit
    static let tapTarget: CGFloat = 44
}

// MARK: - Type
//
// SF Pro Text for words, SF Mono for every digit. Monospaced + tabular so a
// value never jitters as it updates — this is an instrument, not a web page.

enum MarineType {
    static let hero = Font.system(size: 62, weight: .semibold, design: .monospaced)
    static let heroCompact = Font.system(size: 48, weight: .semibold, design: .monospaced)
    static let result = Font.system(size: 28, weight: .semibold, design: .monospaced)
    static let value = Font.system(size: 17, weight: .medium, design: .monospaced)
    static let valueEmphasis = Font.system(size: 17, weight: .semibold, design: .monospaced)
    static let field = Font.system(size: 19, weight: .semibold, design: .monospaced)
    static let mono12 = Font.system(size: 12, weight: .medium, design: .monospaced)
    static let mono11 = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let mono10 = Font.system(size: 10, weight: .medium, design: .monospaced)
    static let label = Font.system(size: 15)
    static let rowTitle = Font.system(size: 16, weight: .semibold)
    static let title = Font.system(size: 30, weight: .bold)
    static let section = Font.system(size: 11, weight: .semibold)
    static let badge = Font.system(size: 9.5, weight: .semibold)
    static let caption = Font.system(size: 12)
}

// MARK: - Formatting
//
// Fixes a real shipped bug: numeric fields inherited the locale decimal
// separator and showed `54,6` on a European locale. Navigational entry is
// always dot-separated here, in every locale.

enum MarineFormat {
    static let posix = Locale(identifier: "en_US_POSIX")

    static func number(_ fraction: ClosedRange<Int> = 0...4) -> FloatingPointFormatStyle<Double> {
        .number.precision(.fractionLength(fraction)).locale(posix)
    }
}

// MARK: - Surfaces

/// The standard card: surface + hairline, no shadow. Shadows disappear in
/// sunlight and glow in the dark — a hairline reads in both.
struct MarineCard<Content: View>: View {
    @Environment(\.marine) private var theme
    var accent: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(theme.palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: MarineMetrics.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MarineMetrics.cardRadius, style: .continuous)
                    .strokeBorder(accent?.opacity(0.32) ?? theme.palette.hairline, lineWidth: 1)
            )
            .padding(.horizontal, MarineMetrics.gutter)
    }
}

/// Section label. Replaces the old `ToolSection` header; call sites keep the
/// same shape: `ToolSection(title:) { rows }`.
struct ToolSection<Content: View>: View {
    @Environment(\.marine) private var theme
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(MarineType.section)
                .tracking(1.0)
                .foregroundStyle(theme.palette.inkDim)
                .padding(.horizontal, MarineMetrics.gutter + 8)
            MarineCard { content }
        }
        .padding(.bottom, MarineMetrics.sectionGap)
    }
}

/// A hairline that stops short of the leading edge, table-style.
struct MarineDivider: View {
    @Environment(\.marine) private var theme
    var body: some View {
        theme.palette.hairline
            .frame(height: 1)
            .padding(.leading, MarineMetrics.cardPadding)
    }
}

// MARK: - Rows

/// A labelled, unit-suffixed result. Same signature as the structural version.
struct ResultRow: View {
    @Environment(\.marine) private var theme
    let label: String
    let value: String
    var unit: String = ""
    var emphasis: Bool = false
    var identifier: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(MarineType.label)
                .foregroundStyle(theme.palette.inkDim)
            Spacer(minLength: 12)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(emphasis ? MarineType.result : MarineType.value)
                    .foregroundStyle(emphasis ? theme.palette.water : theme.palette.ink)
                if !unit.isEmpty {
                    Text(unit)
                        .font(MarineType.caption)
                        .foregroundStyle(theme.palette.inkDim)
                }
            }
            .monospacedDigit()
            .accessibilityIdentifier(identifier ?? "result.\(label)")
        }
        .frame(minHeight: MarineMetrics.rowHeight)
        .padding(.horizontal, MarineMetrics.cardPadding)
    }
}

/// A numeric field with an explicit range — every numeric input in this app has
/// one, because the Kits guard illegal domains with `precondition`.
///
/// Three deliberate changes from the structural version:
///   1. POSIX formatting, so the separator is always "." (the `54,6` bug).
///   2. The legal range is printed under the label — it is information, not a trap.
///   3. 44 pt −/+ targets, for a wet hand in motion. They clamp, they never wrap.
struct NumberField: View {
    @Environment(\.marine) private var theme
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var unit: String = ""
    var step: Double = 1
    var fraction: ClosedRange<Int> = 0...4
    var identifier: String? = nil

    private var rangeText: String {
        let f = MarineFormat.number(0...2)
        return "\(range.lowerBound.formatted(f)) … \(range.upperBound.formatted(f))"
    }

    private func nudge(_ delta: Double) {
        value = min(max(value + delta, range.lowerBound), range.upperBound)
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(label).font(MarineType.label).foregroundStyle(theme.palette.ink)
                    if !unit.isEmpty {
                        Text(unit).font(MarineType.label).foregroundStyle(theme.palette.inkDim)
                    }
                }
                Text(rangeText)
                    .font(MarineType.mono10)
                    .foregroundStyle(theme.palette.inkDim)
            }
            Spacer(minLength: 8)

            stepper("minus") { nudge(-step) }

            TextField(label, value: $value, format: MarineFormat.number(fraction))
                .multilineTextAlignment(.trailing)
                .font(MarineType.field)
                .monospacedDigit()
                .foregroundStyle(theme.palette.ink)
                .frame(minWidth: 74, maxWidth: 110)
                .padding(.vertical, 3)
                .overlay(alignment: .bottom) {
                    theme.palette.water.opacity(0.35).frame(height: 1.5)
                }
                #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
                #endif
                .accessibilityIdentifier(identifier ?? "input.\(label)")
                .onChange(of: value) { _, new in
                    if new < range.lowerBound { value = range.lowerBound }
                    if new > range.upperBound { value = range.upperBound }
                }

            stepper("plus") { nudge(step) }
        }
        .frame(minHeight: MarineMetrics.controlHeight + 4)
        .padding(.horizontal, 12)
    }

    private func stepper(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                // 44 pt is the HIG minimum and what this control's own doc comment
                // promises ("for a wet hand in motion"); it was shipping at 40.
                .frame(width: MarineMetrics.tapTarget, height: MarineMetrics.tapTarget)
                .background(theme.palette.ink.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: MarineMetrics.controlRadius,
                                                 style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.palette.water)
        .accessibilityHidden(true) // the TextField carries the identifier
    }
}

/// Segmented choice, restyled. Keeps `accessibilityIdentifier` on the control.
struct MarineSegmented<T: Hashable>: View {
    @Environment(\.marine) private var theme
    @Binding var selection: T
    let options: [(value: T, title: String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.title)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(selected ? theme.palette.water : .clear)
                        .foregroundStyle(selected ? theme.palette.surface : theme.palette.inkDim)
                }
                .buttonStyle(.plain)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(theme.palette.hairline, lineWidth: 1))
    }
}

// MARK: - Provenance
//
// App Review 4.3(b): the differentiators must be VISIBLE, not merely true in the
// code. So provenance is two surfaces, not a footnote — a badge strip that never
// scrolls out of the first screenful, and a named-authority footer per tool.

struct ProvenanceBadges: View {
    @Environment(\.marine) private var theme
    var items: [String] = ["Offline", "NOAA-validated", "No subscription"]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(items, id: \.self) { item in
                Text(item.uppercased())
                    .font(MarineType.badge)
                    .tracking(0.7)
                    .foregroundStyle(theme.palette.water)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(theme.palette.water.opacity(0.09),
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(theme.palette.water.opacity(0.22), lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .accessibilityIdentifier("result.provenanceBadges")
    }
}

struct ProvenanceFooter: View {
    @Environment(\.marine) private var theme
    let tool: Tool
    /// Optional measured residual, e.g. "7.6 mm rms over four years of hourly
    /// predictions at this station."
    var evidence: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PROVENANCE")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(theme.palette.inkDim)
            Text("Computed on this device by \(tool.kit)")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.palette.ink)
            Text("Validated against \(tool.oracle)." + (evidence.map { " \($0)" } ?? ""))
                .font(MarineType.caption)
                .foregroundStyle(theme.palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .overlay(RoundedRectangle(cornerRadius: MarineMetrics.cardRadius, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .foregroundStyle(theme.palette.ink.opacity(0.22)))
        .padding(.horizontal, MarineMetrics.gutter)
        .accessibilityIdentifier("result.provenance.\(tool.rawValue)")
    }
}

/// MODEL CAVEAT surface. The text is honesty, not filler — it gets its own
/// framed disclosure with a caution glyph so it reads as a stated limit rather
/// than small print.
struct ModelCaveat: View {
    @Environment(\.marine) private var theme
    let title: String
    let text: String
    var trailing: String? = nil
    @State private var expanded = true

    var body: some View {
        MarineCard(accent: theme.palette.caution) {
            VStack(alignment: .leading, spacing: 0) {
                Button { expanded.toggle() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.palette.caution)
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.palette.caution)
                        Spacer(minLength: 8)
                        if let trailing {
                            Text(trailing)
                                .font(MarineType.mono11)
                                .foregroundStyle(theme.palette.inkDim)
                        }
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.palette.caution)
                    }
                    .frame(minHeight: MarineMetrics.rowHeight)
                    .padding(.horizontal, MarineMetrics.cardPadding)
                }
                .buttonStyle(.plain)

                if expanded {
                    Text(text)
                        .font(MarineType.caption)
                        .foregroundStyle(theme.palette.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 44)
                        .padding(.trailing, MarineMetrics.cardPadding)
                        .padding(.bottom, 12)
                }
            }
        }
        .padding(.bottom, MarineMetrics.sectionGap)
    }
}

// MARK: - Screen scaffold

/// Every tool screen is the same shape: title, provenance badges, then content
/// on the canvas. Replaces `Form { … }.formStyle(.grouped)`.
struct ToolScreen<Content: View>: View {
    @Environment(\.marine) private var theme
    let tool: Tool
    var badges: [String] = ["Offline", "NOAA-validated", "No subscription"]
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MARINE NAV")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(1.0)
                        .foregroundStyle(theme.palette.inkDim)
                    Text(tool.title)
                        .font(MarineType.title)
                        .foregroundStyle(theme.palette.ink)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)

                ProvenanceBadges(items: badges)
                    .padding(.vertical, 13)

                content
            }
            .padding(.bottom, 32)
        }
        .background(theme.palette.canvas)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbarBackground(theme.palette.canvas, for: .automatic)
        // NB: no `.preferredColorScheme` here. The root (`ContentView`) is the single
        // owner of the colour scheme, and it passes nil in `.auto` so the system wins.
        // Forcing it here made `.auto` resolve once and then read its own forced value
        // back out of `\.colorScheme`, so it never followed a later system change.
    }
}

/// The hero readout: the one number a two-second glance must land on, flush to
/// the canvas rather than boxed in a row.
struct HeroReadout: View {
    @Environment(\.marine) private var theme
    let value: String
    let unit: String
    /// e.g. "RISING" / "FLOODING"
    let stateLabel: String
    let stateValue: String
    /// Positive = rising / flooding.
    let positive: Bool
    /// e.g. ("High", "11:58", "2h 17m")
    var nextEvent: (kind: String, time: String, countdown: String)?
    var identifier: String
    /// Identifier for the state line (rate of change / set). It lands on the real
    /// visible `Text` — an invisible carrier would not resolve: `.hidden()` removes
    /// a view from the accessibility tree entirely.
    var stateIdentifier: String? = nil

    private var glyph: String { positive ? "arrow.up" : "arrow.down" }
    private var stateColor: Color {
        theme.palette.signByGlyph ? theme.palette.ink
                                  : (positive ? theme.palette.flood : theme.palette.ebb)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(value)
                    .font(MarineType.hero)
                    .monospacedDigit()
                    .foregroundStyle(theme.palette.heroInk)
                    .accessibilityIdentifier(identifier)
                Text(unit)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(theme.palette.inkDim)
            }
            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    Image(systemName: glyph).font(.system(size: 14, weight: .bold))
                    Text(stateLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(0.4)
                    Text(stateValue)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .accessibilityIdentifier(stateIdentifier ?? "\(identifier).state")
                }
                .foregroundStyle(stateColor)

                if let next = nextEvent {
                    (Text(next.kind + " ").foregroundStyle(theme.palette.inkDim)
                     + Text(next.time).font(.system(size: 14, weight: .medium, design: .monospaced))
                     + Text(" in ").foregroundStyle(theme.palette.inkDim)
                     + Text(next.countdown).font(.system(size: 14, weight: .medium, design: .monospaced)))
                        .font(.system(size: 14))
                        .foregroundStyle(theme.palette.ink)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }
}

// MARK: - Colour helper

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
