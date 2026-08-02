import WidgetKit
import SwiftUI
import EphemerisKit

/// The complications that need **no observer position**.
///
/// Planetary longitudes are geocentric — pure functions of time — so retrograde status and the
/// next event both work on a watch that has never spoken to the phone. Neither can ever show an
/// empty state, which is why these two survived and the two that needed more did not.
///
/// Both are `StaticConfiguration` — informational only, nothing user-selectable.

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
        StaticConfiguration(kind: "eph.retrograde.v2", provider: RetroProvider()) { e in
            RetroView(entry: e).containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Retrograde")
        .description("Which planets are retrograde right now.")
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
        StaticConfiguration(kind: "eph.nextevent.v2", provider: NextEventProvider()) { e in
            NextEventView(entry: e).containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Next Event")
        .description("The next ingress, lunation or station, with its real date.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
