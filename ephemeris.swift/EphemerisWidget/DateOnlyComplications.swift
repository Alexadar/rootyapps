import WidgetKit
import SwiftUI
import EphemerisKit

/// The three complications that need **no observer position**.
///
/// Planetary longitudes are geocentric — pure functions of time — so retrograde status, Moon
/// phase and the next event all work on a watch that has never spoken to the phone. Only the
/// Ascendant needs a place. That split is worth preserving deliberately: it means three of the
/// four complications can never show an empty state, and the app is useful on the wrist
/// immediately after install.
///
/// All three are `StaticConfiguration` — informational only, nothing user-selectable.

// MARK: Retrograde

struct RetroEntry: TimelineEntry {
    let date: Date
    let retrograde: [CelestialBody]
    /// When the next station occurs, so the complication can say "until".
    let nextStation: Date?
}

struct RetroProvider: TimelineProvider {
    func placeholder(in c: Context) -> RetroEntry {
        RetroEntry(date: .now, retrograde: [.mercury], nextStation: nil)
    }
    func getSnapshot(in c: Context, completion: @escaping (RetroEntry) -> Void) {
        completion(Self.entry(at: .now))
    }
    func getTimeline(in c: Context, completion: @escaping (Timeline<RetroEntry>) -> Void) {
        // Retrograde state only changes at a station, so one entry now plus a reload scheduled
        // for the next one. Nothing between those two instants can alter the answer — polling
        // daily would be pure waste.
        let e = Self.entry(at: .now)
        let next = e.nextStation ?? Date.now.addingTimeInterval(7 * 86_400)
        completion(Timeline(entries: [e], policy: .after(next)))
    }

    static func entry(at date: Date) -> RetroEntry {
        let bodies = CelestialBody.allCases.filter {
            $0 != .sun && $0 != .moon && Ephemeris.isRetrograde($0, at: date)
        }
        let window = DateInterval(start: date, end: date.addingTimeInterval(200 * 86_400))
        let station = EventTimeline.allEvents(in: window)
            .first { $0.kind == .stationRetrograde || $0.kind == .stationDirect }?.date
        return RetroEntry(date: date, retrograde: bodies, nextStation: station)
    }
}

struct RetroView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RetroEntry

    private var glyphs: String {
        entry.retrograde.map { $0.glyph + "\u{FE0E}" }.joined(separator: " ")
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(verbatim: entry.retrograde.isEmpty ? "No retrogrades" : "\(glyphs) ℞")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "RETROGRADE").font(.caption2).foregroundStyle(.secondary)
                Text(verbatim: entry.retrograde.isEmpty ? "None" : glyphs)
                    .font(.headline).foregroundStyle(.orange)
                if let s = entry.nextStation {
                    Text(verbatim: "next station \(s.formatted(.dateTime.day().month(.abbreviated)))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        default:
            VStack(spacing: 0) {
                Text(verbatim: entry.retrograde.isEmpty ? "—" : "℞")
                    .font(.title3).foregroundStyle(.orange)
                if !entry.retrograde.isEmpty {
                    Text(verbatim: "\(entry.retrograde.count)").font(.system(size: 11))
                }
            }
        }
    }
}

struct RetrogradeComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Retrograde", provider: RetroProvider()) { e in
            RetroView(entry: e).containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Retrograde")
        .description("Which planets are retrograde right now.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: Moon

struct MoonEntry: TimelineEntry {
    let date: Date
    let sign: ZodiacSign
    /// 0 = new, 1 = full. Kept for the percentage label.
    let illumination: Double
    /// Sun–Moon elongation in degrees — the one quantity the drawn shape needs.
    let elongation: Double
    let waxing: Bool
}

struct MoonProvider: TimelineProvider {
    func placeholder(in c: Context) -> MoonEntry { Self.entry(at: .now) }
    func getSnapshot(in c: Context, completion: @escaping (MoonEntry) -> Void) {
        completion(Self.entry(at: .now))
    }
    func getTimeline(in c: Context, completion: @escaping (Timeline<MoonEntry>) -> Void) {
        // The Moon moves ~13°/day, so its sign changes every ~2.3 days and its phase visibly
        // every few hours. Six-hourly entries for a day is plenty and cheap.
        let entries = stride(from: 0, through: 24, by: 6).map {
            Self.entry(at: Date.now.addingTimeInterval(Double($0) * 3600))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    static func entry(at date: Date) -> MoonEntry {
        let moon = Ephemeris.longitude(of: .moon, at: date)
        let sun  = Ephemeris.longitude(of: .sun,  at: date)
        let elongation = AstroMath.norm360(moon - sun)
        // Illuminated fraction from the phase angle: 0° new, 180° full.
        let illum = (1 - cos(elongation * .pi / 180)) / 2
        return MoonEntry(date: date,
                         sign: ZodiacSign.from(longitude: moon),
                         illumination: illum,
                         elongation: elongation,
                         waxing: elongation < 180)
    }
}

struct MoonView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MoonEntry

    private var phaseName: String {
        switch entry.illumination {
        case ..<0.03:  return "New"
        case ..<0.47:  return entry.waxing ? "Waxing crescent" : "Waning crescent"
        case ..<0.53:  return entry.waxing ? "First quarter" : "Last quarter"
        case ..<0.97:  return entry.waxing ? "Waxing gibbous" : "Waning gibbous"
        default:       return "Full"
        }
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(verbatim: "☾\u{FE0E} \(entry.sign.glyph)\u{FE0E} \(Int(entry.illumination * 100))%")
        case .accessoryRectangular:
            HStack(spacing: 8) {
                MoonDisc(elongation: entry.elongation).frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: phaseName).font(.caption)
                    Text(verbatim: "in \(entry.sign.name)").font(.caption2).foregroundStyle(.secondary)
                }
            }
        default:
            MoonDisc(elongation: entry.elongation)
        }
    }
}

struct MoonComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MoonPhase", provider: MoonProvider()) { e in
            MoonView(entry: e).containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Moon")
        .description("Moon phase and the sign it is in.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: Next event

struct NextEventEntry: TimelineEntry {
    let date: Date
    let text: String
    let when: Date?
}

struct NextEventProvider: TimelineProvider {
    func placeholder(in c: Context) -> NextEventEntry {
        NextEventEntry(date: .now, text: "Mars enters Gemini", when: .now)
    }
    func getSnapshot(in c: Context, completion: @escaping (NextEventEntry) -> Void) {
        completion(Self.entry(at: .now))
    }
    func getTimeline(in c: Context, completion: @escaping (Timeline<NextEventEntry>) -> Void) {
        // One entry per upcoming event, each valid from the moment the previous one passes, so
        // the complication rolls forward on its own with a single reload.
        let events = Self.upcoming(from: .now, limit: 8)
        var entries = [Self.entry(at: .now)]
        for e in events {
            entries.append(NextEventEntry(date: e.date.addingTimeInterval(1),
                                          text: Self.describe(e), when: e.date))
        }
        completion(Timeline(entries: entries, policy: .after(events.last?.date ?? .now.addingTimeInterval(86_400))))
    }

    static func upcoming(from date: Date, limit: Int) -> [AstroEvent] {
        let window = DateInterval(start: date, end: date.addingTimeInterval(200 * 86_400))
        return Array(EventTimeline.allEvents(in: window).filter { $0.date > date }.prefix(limit))
    }
    static func entry(at date: Date) -> NextEventEntry {
        guard let e = upcoming(from: date, limit: 1).first else {
            return NextEventEntry(date: date, text: "—", when: nil)
        }
        return NextEventEntry(date: date, text: describe(e), when: e.date)
    }
    /// English on purpose: a widget extension resolves LocalizedStringKey against its own bundle,
    /// and the Kit's label is already the catalog key elsewhere. Localizing this properly needs
    /// the same pattern-key treatment the app uses — tracked, not faked here.
    static func describe(_ e: AstroEvent) -> String { e.label() }
}

struct NextEventView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextEventEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(verbatim: entry.text)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "NEXT").font(.caption2).foregroundStyle(.secondary)
                Text(verbatim: entry.text).font(.caption).lineLimit(2)
                if let w = entry.when {
                    Text(w, format: .dateTime.day().month(.abbreviated))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        default:
            Text(verbatim: "✦").font(.title3)
        }
    }
}

struct NextEventComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextEvent", provider: NextEventProvider()) { e in
            NextEventView(entry: e).containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Next Event")
        .description("The next ingress, lunation or station, with its real date.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
