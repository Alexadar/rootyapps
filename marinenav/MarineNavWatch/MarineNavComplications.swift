import SwiftUI
import WidgetKit
import TidesKit

// ─────────────────────────────────────────────────────────────────────────────
// F6 · COMPLICATIONS / SMART STACK
//
// The structural advantage worth exploiting: harmonic synthesis produces EXACT
// future values with no network. Every server-backed tide complication is stuck
// refreshing on a budget; this one hands WidgetKit a LONG PRECOMPUTED TIMELINE —
// 5-minute entries out to 24 h (289 entries) — and never needs to wake early.
// One evaluation of the day's constituents fills a whole day of entries.
//
// ⚠ TRAP, from the phone team's notes: adopt
//     .containerBackground(.clear, for: .widget)
// or the complication renders correctly in the Simulator and GREY on a real
// device.
//
// ZERO math: `Harmonics.heights` / `.extremes` / `.slope` produce everything the
// timeline carries. The provider only samples, formats, and packs.
// ─────────────────────────────────────────────────────────────────────────────

struct TideEntry: TimelineEntry {
    let date: Date
    /// Nil = no station chosen yet.
    let station: String?
    let zone: String
    /// Formatted height, e.g. "3.56".
    let height: String
    let unit: String
    /// True = rising.
    let rising: Bool
    /// Position of `height` between the day's low and high, 0…1 — the gauge's
    /// value, so the circular family reads with NO colour at all.
    let fraction: Double
    /// Next turn.
    let nextKind: String?
    let nextTime: String?
    let nextDate: Date?
    /// True when this entry is past the end of the precomputed timeline.
    let stale: Bool

    static func noStation(_ date: Date) -> TideEntry {
        TideEntry(date: date, station: nil, zone: "", height: "—", unit: "",
                  rising: true, fraction: 0.5, nextKind: nil, nextTime: nil,
                  nextDate: nil, stale: false)
    }
}

struct TideTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TideEntry {
        TideEntry(date: Date(), station: "Station", zone: "PDT", height: "3.56", unit: "ft",
                  rising: true, fraction: 0.62, nextKind: "High", nextTime: "11:58",
                  nextDate: Date().addingTimeInterval(8220), stale: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (TideEntry) -> Void) {
        completion(entries(count: 1).first ?? .noStation(Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TideEntry>) -> Void) {
        let list = entries(count: 289)          // 24 h at 5-minute spacing
        // `.atEnd`: the last entry is 24 h out, and by then a new day's
        // constituents should be evaluated. No early refresh, no budget anxiety.
        completion(Timeline(entries: list, policy: .atEnd))
    }

    /// One Kit evaluation pass, then 289 samples of it.
    private func entries(count: Int) -> [TideEntry] {
        // Nonisolated reads: this runs in the widget extension, off the main actor.
        guard let rec = StationCatalog.tideStations
                .first(where: { $0.id == WatchStationStore.storedTideStationID })
        else { return [.noStation(Date())] }

        let unit = WatchStationStore.storedUnit
        let station = rec.station(unit: unit)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = rec.timeZone
        let now = Date()
        let dayStart = cal.startOfDay(for: now)
        let extremes = Harmonics.extremes(station, start: dayStart, hours: 48)
        let dayLo = extremes.filter { $0.kind == .low }.map(\.height).min() ?? 0
        let dayHi = extremes.filter { $0.kind == .high }.map(\.height).max() ?? 1
        let span = max(dayHi - dayLo, 0.0001)
        let zone = rec.timeZone.abbreviation(for: now) ?? rec.timeZoneIdentifier
        let unitLabel = unit == .meters ? "m" : "ft"

        return (0..<count).map { i in
            let date = now.addingTimeInterval(Double(i) * 300)
            let h = Harmonics.height(station, at: date)
            let next = extremes.first { $0.date > date }
            return TideEntry(
                date: date,
                station: rec.name,
                zone: zone,
                height: h.formatted(WatchFormat.number(2...2)),
                unit: unitLabel,
                rising: Harmonics.slope(station, at: date) >= 0,
                fraction: min(max((h - dayLo) / span, 0), 1),
                nextKind: next.map { $0.kind == .high ? "High" : "Low" },
                nextTime: next.map { WatchFormat.time($0.date, zone: rec.timeZone) },
                nextDate: next?.date,
                stale: false)
        }
    }
}

// MARK: - Families
//
// Every family states the same four things in as much detail as it has room for:
// height, trend GLYPH, next turn, countdown. None of them uses hue as a signal —
// accessory families are tinted by the watch face anyway, which is exactly why
// colour can never carry meaning here.

struct TideComplicationView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.watchTheme) private var theme
    let entry: TideEntry

    var body: some View {
        switch family {
        case .accessoryCircular:  circular
        case .accessoryCorner:    corner
        case .accessoryRectangular: rectangular
        case .accessoryInline:    inline
        default:                  circular
        }
    }

    private var trend: String { entry.rising ? "arrow.up" : "arrow.down" }

    /// Circular: a gauge whose NEEDLE POSITION is the tide's position between the
    /// day's low and high — legible with no colour and at a glance. The numeral
    /// sits inside it.
    private var circular: some View {
        Group {
            if entry.station == nil {
                VStack(spacing: 0) {
                    Image(systemName: "water.waves").font(.system(size: 12))
                    Text("Set").font(.system(size: 11, weight: .semibold))
                }
                .accessibilityLabel("Marine Nav: no tide station chosen yet")
            } else {
                Gauge(value: entry.fraction) {
                    Image(systemName: trend).font(.system(size: 9, weight: .bold))
                } currentValueLabel: {
                    Text(entry.height)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                }
                .gaugeStyle(.accessoryCircular)
                .accessibilityLabel(spokenNow)
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    /// Corner: the numeral on the curved text edge, the trend and next turn in
    /// the corner label.
    private var corner: some View {
        Text(entry.height)
            .font(.system(size: 17, weight: .semibold, design: .monospaced))
            .monospacedDigit()
            .widgetLabel {
                Text(entry.station == nil
                     ? "Choose a station"
                     : "\(entry.rising ? "↑" : "↓") \(entry.nextKind ?? "") \(entry.nextTime ?? "")")
            }
            .accessibilityLabel(spokenNow)
            .containerBackground(.clear, for: .widget)
    }

    /// Rectangular: the only family with room for the zone label, so it always
    /// carries it — a tide time with no zone is the bug that started all this.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let station = entry.station {
                HStack(spacing: 3) {
                    Text(station)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(entry.zone)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(entry.height)
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                    Text(entry.unit).font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Image(systemName: trend).font(.system(size: 11, weight: .bold))
                    Spacer(minLength: 0)
                }
                if let kind = entry.nextKind, let time = entry.nextTime, let d = entry.nextDate {
                    HStack(spacing: 3) {
                        Text("\(kind) \(time)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                        Text("in")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        // WidgetKit renders this live, so the countdown stays
                        // right between timeline entries.
                        Text(d, style: .timer)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                    }
                }
            } else {
                Text("Marine Nav").font(.system(size: 12, weight: .medium))
                Text("Open to choose a tide station")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(spokenFull)
        .containerBackground(.clear, for: .widget)
    }

    /// Inline: one line, no glyph beyond the arrow — the face gives it no room.
    private var inline: some View {
        Group {
            if entry.station == nil {
                Text("Marine Nav — choose a station")
            } else {
                Text("\(entry.height)\(entry.unit) \(entry.rising ? "↑" : "↓")  "
                     + "\(entry.nextKind ?? "") \(entry.nextTime ?? "") \(entry.zone)")
            }
        }
        .accessibilityLabel(spokenFull)
        .containerBackground(.clear, for: .widget)
    }

    // MARK: VoiceOver — quantity, unit, zone. Always.

    private var spokenNow: String {
        guard let station = entry.station else { return "Marine Nav: no station chosen" }
        return "\(entry.height) \(entry.unit == "m" ? "metres" : "feet"), "
             + "\(entry.rising ? "rising" : "falling"), at \(station)."
    }

    private var spokenFull: String {
        guard entry.station != nil else { return "Marine Nav: no station chosen" }
        var s = spokenNow
        if let kind = entry.nextKind, let time = entry.nextTime {
            s += " Next \(kind.lowercased()) water \(time) \(entry.zone)."
        }
        return s
    }
}

struct TideComplication: Widget {
    let kind = "MarineNavTide"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TideTimelineProvider()) { entry in
            TideComplicationView(entry: entry)
        }
        .configurationDisplayName("Tide now")
        .description("Height, trend and the next high or low — computed on this device, offline.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner,
                            .accessoryRectangular, .accessoryInline])
    }
}

@main
struct MarineNavComplications: WidgetBundle {
    var body: some Widget {
        TideComplication()
    }
}

#Preview("Circular", as: .accessoryCircular) {
    TideComplication()
} timeline: {
    TideEntry(date: .now, station: "San Francisco", zone: "PDT", height: "3.56", unit: "ft",
              rising: true, fraction: 0.62, nextKind: "High", nextTime: "11:58",
              nextDate: .now.addingTimeInterval(8220), stale: false)
    TideEntry.noStation(.now)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    TideComplication()
} timeline: {
    TideEntry(date: .now, station: "San Francisco", zone: "PDT", height: "3.56", unit: "ft",
              rising: true, fraction: 0.62, nextKind: "High", nextTime: "11:58",
              nextDate: .now.addingTimeInterval(8220), stale: false)
}
