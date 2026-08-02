// Accessory families (and `widgetLabel`) exist only on watchOS and iOS — macOS widgets are
// system-sized only, so the whole file is compiled out there. The synchronized file group puts
// this file in all three widget targets, so this guard is what keeps it inert on the Mac.
#if os(watchOS) || os(iOS)
import WidgetKit
import SwiftUI
import SpaceWeatherFeed
import GeomagKit
import FlareKit

/// What a complication is ABOUT.
///
/// The two kinds (geomagnetic, solar) differ only in which numbers they read and which scale those
/// numbers live on, so every family layout is written once and asks the topic for its values.
/// Without this the four families would be duplicated twice over.
enum ComplicationTopic {
    case kp, flares

    /// Shown in the watch-face picker. Terse on purpose: that list truncates hard, and German and
    /// CJK expand well past English here.
    var title: String.LocalizationValue {
        switch self {
        case .kp:     return "Kp now"
        case .flares: return "Solar flares"
        }
    }

    var detail: String.LocalizationValue {
        switch self {
        case .kp:     return "Planetary Kp now, and the 24-hour peak."
        case .flares: return "Latest flare class, and the strongest of the last 24 hours."
        }
    }

    /// One fact a face can show, plus the scale it sits on.
    ///
    /// `code` is not decoration and neither is `value`: tinted faces flatten every hue to one tint,
    /// so the marker's POSITION on the bar and the "G2"/"R1" text are what actually carry severity
    /// once the gradient is gone. The colour ramp is the third, optional signal — never the only one.
    struct Reading {
        let id: String                  // "KP" / "FLR" — a code, never translated
        let hero: String                // "3.7" / "M1.0"
        let code: String                // "G1" / "R2" / "OK"
        let peak: String?               // "5.3" / "M3.2 ×4"
        let hasData: Bool               // false = nothing was ever fetched, NOT "measured quiet"
        let value: Double?              // marker position; nil when there is nothing honest to draw
        let bounds: ClosedRange<Double>
        let minLabel: String            // bar end captions: "0"/"9", "A"/"X"
        let maxLabel: String
        let ramp: Gradient
        let spoken: String
    }

    func reading(_ s: SpaceWeatherSnapshot) -> Reading {
        switch self {
        case .kp:     return Self.kp(s)
        case .flares: return Self.flares(s)
        }
    }

    /// The geomagnetic level, from the preciser publisher — see `SpaceWeatherSnapshot.geomagNow`.
    /// A face is the surface where the lag hurts most: it is glanced at, not studied, and the
    /// 3-hourly Kp can sit a whole quiet interval behind a storm that has already begun.
    private static func kp(_ s: SpaceWeatherSnapshot) -> Reading {
        let level = s.geomagNow
        let g = s.geomagGScale
        return Reading(
            id: "KP",
            hero: Fmt.num(level, 1),
            // "OK" is a claim that we measured a quiet field. Without data we measured nothing,
            // and saying OK there is the same lie as showing a zero-length bar.
            code: g > 0 ? "G\(g)" : (level != nil ? "OK" : "—"),
            // Same source as the hero: an Hp30 level beside a Kp peak would read as a trend
            // between two different indices.
            peak: s.geomagPeak24h().map { Fmt.num($0, 1) },
            hasData: level != nil,
            // Hpo is defined on the Kp 0…9 scale, so this stays the one honest raw-value bar here.
            value: level.map { min(max($0, 0), 9) },
            bounds: 0...9,
            minLabel: "0",
            maxLabel: "9",
            ramp: ComplicationRamp.kp,
            spoken: SWText.str("Geomagnetic level \(Fmt.num(level, 1)), level G\(g)"))
    }

    private static func flares(_ s: SpaceWeatherSnapshot) -> Reading {
        let f = s.flare
        let cls = f.map { $0.latestFlare?.maxClass ?? $0.currentClass }
        let r = f.map { $0.latestFlare?.rScale ?? $0.rScale } ?? 0
        let n = f?.count24h ?? 0
        let peak = (f?.peak24h?.maxClass).map { n > 1 ? "\($0) ×\(n)" : $0 }
        return Reading(
            id: "FLR",
            hero: cls ?? "—",
            code: r > 0 ? "R\(r)" : (cls != nil ? "OK" : "—"),
            peak: peak,
            hasData: cls != nil,
            value: cls.flatMap(decade),
            bounds: 0...1,
            minLabel: "A",
            maxLabel: "X",
            ramp: ComplicationRamp.flare,
            spoken: SWText.str("Latest flare \(cls ?? "—")"))
    }

    /// Flare class on a log-decade ladder, A1 → X10, clamped to 0…1.
    ///
    /// The obvious alternative — drive the bar from the NOAA R scale — is wrong: R is 0 for
    /// everything below M1, which is most days, so the bar would sit dead-empty through the whole
    /// A/B/C range and a busy C-class day would look identical to no data. Flux is continuous, and
    /// the letter boundaries land on fifths, so "one fifth per letter" is a readable mental model.
    /// Above X10 it pins full while the TEXT still says X17 — the unbounded tail belongs in the
    /// numeral, not the bar. `Flare.flux(forClass:)` is the Kit's oracle-tested parser.
    /// `nonisolated` because it is passed to `flatMap` as an unapplied function reference, which
    /// drops the enclosing main-actor isolation and warns. It is pure arithmetic either way.
    private nonisolated static func decade(_ cls: String) -> Double? {
        guard let flux = Flare.flux(forClass: cls), flux > 0 else { return nil }
        return min(max((log10(flux) + 8) / 5, 0), 1)
    }
}

// MARK: - Severity ramp

/// The bar gradient, keyed to NOAA's own storm-scale colours.
///
/// Deliberately NOT `SWPalette`: the night preset is red-shifted end to end, which would turn a
/// green→red severity ramp into red→red, and a complication cannot reliably know the user's theme
/// anyway. These are fixed so the bar agrees with any NOAA chart the user cross-checks.
enum ComplicationRamp {
    private static func rgb(_ hex: UInt32) -> Color {
        Color(.sRGB,
              red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }

    private static let quiet   = rgb(0x45D18A)   // below scale
    private static let minor   = rgb(0xF6EB14)   // G1 / R1
    private static let moderate = rgb(0xFFC800)  // G2
    private static let strong  = rgb(0xFF9600)   // G3 / R2
    private static let severe  = rgb(0xFF0000)   // G4 / R3
    private static let extreme = rgb(0xC80000)   // G5 / R4

    /// Stops sit exactly on the G-scale boundaries: G1=Kp5, G2=6, G3=7, G4=8, G5=9, over 0…9.
    static let kp = Gradient(stops: [
        .init(color: quiet,    location: 0.0),
        .init(color: quiet,    location: 0.500),   // Kp 4.5 — still below G1
        .init(color: minor,    location: 5.0 / 9),
        .init(color: moderate, location: 6.0 / 9),
        .init(color: strong,   location: 7.0 / 9),
        .init(color: severe,   location: 8.0 / 9),
        .init(color: extreme,  location: 1.0),
    ])

    /// Same colours on the log-decade ladder: M1 (=R1) is 0.6, M5 (=R2) 0.74, X1 (=R3) 0.8,
    /// X10 (=R4) 1.0. Everything quiet lives in the bottom 60%, which is where most days sit.
    static let flare = Gradient(stops: [
        .init(color: quiet,   location: 0.0),
        .init(color: quiet,   location: 0.55),
        .init(color: minor,   location: 0.60),
        .init(color: strong,  location: 0.74),
        .init(color: severe,  location: 0.80),
        .init(color: extreme, location: 1.0),
    ])
}

// MARK: - Views

/// One view for every accessory family, parameterised by topic.
///
/// Deliberately does NOT read `SWMode.shared` and never touches the theme palette. Faces render in
/// `.accented` and `.vibrant`, which flatten colour to a single tint — so meaning lives in the text
/// and in the marker position, both of which survive monochrome. `SWMode` defaults to `.simple` on a
/// watch that never received the phone's context, which would otherwise render the wrong variant.
struct ComplicationView: View {
    let topic: ComplicationTopic
    let entry: SpaceWeatherEntry
    @Environment(\.widgetFamily) private var family

    private var r: ComplicationTopic.Reading { topic.reading(entry.snapshot) }

    var body: some View {
        content
            // Not optional since watchOS 10: a widget that never adopts `containerBackground`
            // renders an "please adopt containerBackground API" notice INSTEAD of its content. In a
            // complication slot that notice has nowhere to fit, so it degrades to a grey blob — on
            // device only, because the simulator renders the content anyway. `.clear` because the
            // watch face draws behind an accessory family; an opaque fill here would be a dark
            // rectangle over the wallpaper.
            .containerBackground(.clear, for: .widget)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(r.spoken))
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryCircular:    circular
        case .accessoryRectangular: rectangular
        case .accessoryInline:      inline
        #if os(watchOS)
        case .accessoryCorner:      corner
        #endif
        // Never a system layout here: these kinds advertise accessory families only, and falling
        // back to `small` would put a phone-sized card in a watch-face slot.
        default:                    rectangular
        }
    }

    // MARK: - Families

    /// The headline: value and level on top, the bar underneath with its scale ends captioned.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(verbatim: "\(r.id) \(r.hero)")
                    .font(.system(.headline, design: .monospaced).weight(.bold))
                    .monospacedDigit()
                    .widgetAccentable()
                Text(verbatim: r.code)
                    .font(.system(.caption2, design: .monospaced).weight(.heavy))
                Spacer(minLength: 0)
                if let peak = r.peak {
                    // "↑5.3" alone reads as a trend arrow; the window is what makes it a peak.
                    Text(verbatim: "24H ↑\(peak)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            bar
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A ring is the circular family's bar — same marker, wrapped.
    @ViewBuilder private var circular: some View {
        if let value = r.value {
            Gauge(value: value, in: r.bounds) {
                Text(verbatim: r.id)
            } currentValueLabel: {
                Text(r.hero).minimumScaleFactor(0.6).lineLimit(1).widgetAccentable()
            }
            .gaugeStyle(.accessoryCircular)
            .tint(r.ramp)
            .widgetLabel { if let peak = r.peak { Text(verbatim: "↑\(peak)") } }
        } else {
            noData
        }
    }

    private var inline: some View {
        // One line, truncated hard — the peak is the first thing to drop.
        Text(verbatim: [r.id, r.hero, r.peak.map { "↑\($0)" }]
            .compactMap { $0 }
            .joined(separator: " "))
    }

    #if os(watchOS)
    /// WidgetKit curves a gauge placed in a corner's label into an arc along the bezel — the same
    /// treatment Apple's own moon-phase and coffee complications use. That arc carries the level;
    /// the small circle keeps the numeral, which a curved numeral would only make harder to read.
    private var corner: some View {
        // The numeral alone is unreadable — "3.7" of what? The bezel arc carries the level, so the
        // circle has to carry the name, and there is only room for it under the value.
        VStack(spacing: -1) {
            Text(r.hero)
                .font(.system(.title3, design: .rounded))
                .monospacedDigit()
            Text(verbatim: r.id)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
            .minimumScaleFactor(0.6).lineLimit(1)
            .widgetAccentable()
            .widgetLabel {
                if let value = r.value {
                    Gauge(value: value, in: r.bounds) { Text(verbatim: r.id) }
                        .tint(r.ramp)
                } else {
                    Text(verbatim: r.code)
                }
            }
    }
    #endif

    // MARK: - Pieces

    @ViewBuilder private var bar: some View {
        if let value = r.value {
            Gauge(value: value, in: r.bounds) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            } minimumValueLabel: {
                Text(verbatim: r.minLabel).font(.system(.caption2, design: .monospaced))
            } maximumValueLabel: {
                Text(verbatim: r.maxLabel).font(.system(.caption2, design: .monospaced))
            }
            .gaugeStyle(.accessoryLinear)
            .tint(r.ramp)
        } else {
            // No bar at all rather than an empty one: a zero-length bar reads as "quiet", which is
            // a measurement. "We don't know" is a different claim and has to look different — and
            // the rectangular family is the one place with room to say it in words.
            Text(SWText.str("no data"))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// Shown when there is no marker to place — either nothing was ever fetched, or we have a class
    /// string the flux parser rejects.
    ///
    /// It must not be an anonymous grey disc. `AccessoryWidgetBackground` alone renders as exactly
    /// that, which is visually identical to a complication that has failed outright — so it always
    /// carries the topic code, and the hero when we have one, to say *which* reading is missing.
    private var noData: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: -2) {
                Text(verbatim: r.id)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(r.hero)
                    .font(.system(.headline, design: .rounded))
                    .monospacedDigit()
                    .widgetAccentable()
            }
            .minimumScaleFactor(0.6)
            .lineLimit(1)
        }
    }
}

// MARK: - The two kinds

/// One factory, two kinds. They share `SpaceWeatherProvider`: WidgetKit asks each installed
/// widget for its own timeline, and that provider already reads the app-group cache first and
/// `merge`s, so several complications on one face coalesce onto one snapshot instead of each
/// firing its own five NOAA requests from the wrist.
enum SWComplication {
    static func config(_ topic: ComplicationTopic) -> some WidgetConfiguration {
        StaticConfiguration(kind: topic.kind, provider: SpaceWeatherProvider()) { entry in
            ComplicationView(topic: topic, entry: entry)
                .environment(\.locale, SWLanguage.sharedLocale)
        }
        .configurationDisplayName(SWText.str(topic.title))
        .description(SWText.str(topic.detail))
        .supportedFamilies(ComplicationTopic.families)
    }
}

extension ComplicationTopic {
    /// Do not change these casually: the system persists the kind string for every complication a
    /// user has placed, and renaming one silently blanks it on their face.
    ///
    /// They have been changed twice, deliberately, chasing a device-side bug: watchOS caches
    /// complication descriptors by identifier, and that cache goes stale when the set of kinds
    /// changes — the slot then renders a placeholder forever and `getTimeline` is never called at
    /// all, which the app cannot detect or recover from. Re-adding the complication, rebooting,
    /// reinstalling and moving `SpaceWeather.*` → `EarthAround.*` all failed to evict it, so this
    /// third namespace is a fresh attempt, not a fix with evidence behind it.
    /// See developer.apple.com/forums/thread/729599.
    ///
    /// Retired, never to be reused: `SpaceWeather`, `SpaceWeather.kp`, `SpaceWeather.flares`,
    /// `SpaceWeather.combined`, `EarthAround.geomagnetic`, `EarthAround.solar`.
    var kind: String {
        switch self {
        case .kp:     return "EAGeomagneticComplication"
        case .flares: return "EASolarComplication"
        }
    }

    /// `accessoryCorner` is watchOS-only — the guard is load-bearing, not tidiness: naming it in an
    /// iOS `supportedFamilies` array fails to compile.
    static var families: [WidgetFamily] {
        #if os(watchOS)
        [.accessoryCorner, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        #else
        [.accessoryCircular, .accessoryRectangular, .accessoryInline]
        #endif
    }
}

struct KpComplication: Widget     { var body: some WidgetConfiguration { SWComplication.config(.kp) } }
struct FlaresComplication: Widget { var body: some WidgetConfiguration { SWComplication.config(.flares) } }

#endif
