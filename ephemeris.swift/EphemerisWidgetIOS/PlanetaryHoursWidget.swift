import WidgetKit
import SwiftUI
import EphemerisKit

/// The planetary-hours widget — the app's most genuinely glanceable value.
///
/// The ruling planet changes several times a day and the answer is worthless five minutes late, so
/// this is the one surface where a widget beats opening the app.
///
/// ## Gate 1: this one needs a place, and that is why the App Group exists
///
/// Unlike the moon widget, hours cannot be derived from the clock — they divide sunrise→sunset at a
/// *location*. A widget extension has its own bundle and therefore its own `UserDefaults.standard`,
/// so before the app group was declared the observer's place written by the app was simply not
/// visible here. `SharedStore` reads the group container; `ChartViewModel.syncShared()` writes it at
/// launch and on every change.
///
/// ## Two honest empty states, neither of them an error
///
/// - **No place set.** The user has never entered one. Say so and name the setting, rather than
///   guessing a location — a guessed place produces a confident, wrong ruler, and nothing about the
///   output looks wrong.
/// - **No sunrise today.** Above the polar circles `PlanetaryHours.hours` returns nil because there
///   is no daylight interval to divide into twelve. That is the correct answer, not a failure.
///
/// The complications that were removed from the watch bundle were removed for failing exactly this:
/// a surface that renders a no-data state forever looks broken rather than honest. The difference
/// here is that both states are reachable, explicable and worded.

// MARK: - Entry

struct HoursEntry: TimelineEntry {
    let date: Date
    /// Nil when there is no saved place at all.
    let placeName: String?
    /// Nil when a place exists but the day has no sunrise/sunset to divide.
    let hour: PlanetaryHours.Hour?
}

// MARK: - Provider

struct HoursProvider: TimelineProvider {

    func placeholder(in context: Context) -> HoursEntry {
        HoursEntry(date: .now, placeName: "—", hour: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (HoursEntry) -> Void) {
        completion(Self.entry(at: .now))
    }

    /// One entry per remaining hour of the planetary day, each valid from the moment the previous
    /// one ends.
    ///
    /// This is the retrograde complication's pattern rather than the moon widget's: the ruler is
    /// **piecewise constant**, so there is nothing to interpolate — it changes at known instants and
    /// is otherwise fixed. Emitting an entry per boundary lets WidgetKit roll the widget forward on
    /// its own with a single reload, instead of waking it on a timer to discover nothing changed.
    func getTimeline(in context: Context, completion: @escaping (Timeline<HoursEntry>) -> Void) {
        let now = Date.now
        guard let location = SharedStore().location else {
            // No place: nothing will change until the user sets one, and setting one reloads the
            // timeline from the app. Ask again tomorrow rather than spinning.
            completion(Timeline(entries: [Self.entry(at: now)],
                                policy: .after(now.addingTimeInterval(6 * 3600))))
            return
        }

        let zone = TimeZone.current
        guard let hours = PlanetaryHours.hours(startingOn: now, at: location, timeZone: zone) else {
            // Polar day or night — retry after the civil day turns over, when it may resolve.
            completion(Timeline(entries: [Self.entry(at: now)],
                                policy: .after(now.addingTimeInterval(6 * 3600))))
            return
        }

        let name = SharedStore().location?.name
        var entries = hours
            .filter { $0.end > now }
            .map { HoursEntry(date: max($0.start, now), placeName: name, hour: $0) }
        if entries.isEmpty { entries = [Self.entry(at: now)] }

        // Reload at the last hour's end, which is the next day's sunrise — exactly when a fresh
        // division has to be solved.
        completion(Timeline(entries: entries,
                            policy: .after(hours.last?.end ?? now.addingTimeInterval(6 * 3600))))
    }

    static func entry(at date: Date) -> HoursEntry {
        let store = SharedStore()
        guard let location = store.location else {
            return HoursEntry(date: date, placeName: nil, hour: nil)
        }
        let hours = PlanetaryHours.hours(startingOn: date, at: location, timeZone: .current)
        return HoursEntry(date: date,
                          placeName: location.name,
                          hour: hours?.first { $0.contains(date) })
    }
}

// MARK: - View

struct PlanetaryHoursView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HoursEntry

    var body: some View {
        if let hour = entry.hour {
            content(hour)
        } else {
            // Worded, not blank. Which of the two states it is matters to the user: one is fixable
            // by them, the other is the sky.
            switch family {
            #if os(iOS)
            case .accessoryInline:
                Text(entry.placeName == nil ? "No place set" : "No sunrise today")
            #endif
            default:
                VStack(spacing: 3) {
                    Text(verbatim: "☉").font(.title3).foregroundStyle(.secondary)
                    Text(entry.placeName == nil ? "Set a place in Ephemeris" : "No sunrise today")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The Kit's English body name IS the catalog key, resolved against this extension's bundle —
    /// the same pattern the app uses. `Text(verbatim:)` here would ship English planet names into
    /// sixteen localized builds.
    private func rulerName(_ body: CelestialBody) -> LocalizedStringKey {
        LocalizedStringKey(body.name)
    }

    @ViewBuilder
    private func content(_ hour: PlanetaryHours.Hour) -> some View {
        switch family {
        #if os(iOS)
        case .accessoryInline:
            // Glyph + live time, deliberately with no localized connective: interpolating a
            // literal "until" alongside the variation selector would bake U+FE0E into the catalog
            // key, and the inline slot has no room for the word anyway.
            Text(verbatim: hour.ruler.glyph + "\u{FE0E} ") + Text(hour.end, style: .time)

        case .accessoryCircular:
            VStack(spacing: 0) {
                Text(verbatim: hour.ruler.glyph + "\u{FE0E}").font(.system(size: 17))
                Text(hour.end, style: .timer)
                    .font(.system(size: 9, weight: .medium))
                    .multilineTextAlignment(.center)
            }

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(hour.isDay ? "Day hour \(hour.index)" : "Night hour \(hour.index - 12)")
                    .font(.caption2).foregroundStyle(.secondary)
                Text(verbatim: hour.ruler.glyph + "\u{FE0E} ") + Text(rulerName(hour.ruler))
                Text(hour.end, style: .timer).font(.caption2).foregroundStyle(.secondary)
            }
        #endif

        default:
            VStack(spacing: 4) {
                Text(verbatim: hour.ruler.glyph + "\u{FE0E}").font(.system(size: 32))
                Text(rulerName(hour.ruler)).font(.headline)
                Text(hour.isDay ? "Day hour \(hour.index)" : "Night hour \(hour.index - 12)")
                    .font(.caption2).foregroundStyle(.secondary)
                // The length is the point of unequal hours: it is 60 minutes only at the equinox.
                Text("\(Int((hour.duration / 60).rounded())) min long")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Widget

struct PlanetaryHoursWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "eph.hours.ios", provider: HoursProvider()) { entry in
            PlanetaryHoursView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Planetary Hour")
        .description("Which planet rules the current hour, and when it ends.")
        #if os(iOS)
        .supportedFamilies([.systemSmall,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
        #else
        .supportedFamilies([.systemSmall])
        #endif
    }
}
