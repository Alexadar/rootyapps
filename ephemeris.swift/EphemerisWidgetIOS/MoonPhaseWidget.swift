import WidgetKit
import SwiftUI
import EphemerisKit

/// The moon-phase widget — the app's only **gate-0** surface.
///
/// Everything else Ephemeris shows is locked behind a birth record. This works on a brand-new
/// install, which is why it is the one widget that can earn a place on a home screen before the
/// user has committed anything.
///
/// ## Why it needs no location, and why that is the point
///
/// Phase, illumination and the dates of the next full and new moon are functions of **time alone** —
/// the Sun–Moon elongation is geocentric. So this can never show an empty state.
///
/// That rule is not incidental. `EphemerisWidgetBundle` records that two watch complications were
/// removed for failing it: a rising-sign complication showed its no-place state because the observer
/// had never reached the watch. `MoonPhases.riseSet` needs a `GeoLocation` and is therefore
/// **deliberately absent** here, however much a moonrise time would suit the surface.
///
/// ## No moon pictogram, on purpose
///
/// The obvious design puts 🌒 on the widget. Every phase emoji is **directional** — 🌒 is lit on the
/// right, which is a *northern-hemisphere* waxing crescent. Below the equator that same moon appears
/// lit on the left, and the glyph is simply wrong.
///
/// Correcting it needs a latitude, and a latitude is exactly the thing this widget must not depend
/// on. So the phase is carried by name, percentage and the waxing/waning word — none of which have a
/// handedness — and `☽` is used as the body's glyph because it denotes *the Moon*, not a phase of it.
/// The drawn, hemisphere-correct disc belongs on the in-app calendar, where a location exists.
///
/// A related history: the previous moon complication's terminator never rendered correctly on device
/// across five attempts and was removed rather than shipped broken. Text first; the disc is earned.

// MARK: - Entry

struct MoonEntry: TimelineEntry {
    let date: Date
    /// Every derived value comes from the Kit, so the widget, the calendar and the notification
    /// scheduler cannot drift apart on what "days until full" means.
    let moon: MoonPhases.Snapshot
}

// MARK: - Provider

struct MoonProvider: TimelineProvider {

    func placeholder(in context: Context) -> MoonEntry { Self.entry(at: .now) }

    func getSnapshot(in context: Context, completion: @escaping (MoonEntry) -> Void) {
        completion(Self.entry(at: .now))
    }

    /// Unlike the retrograde complication — whose answer is piecewise constant and so needs a single
    /// entry plus a reload at the next station — illumination changes *continuously*, by up to about
    /// 3.4 percentage points a day.
    ///
    /// So this pre-computes a day of hourly entries and asks for one reload at the end of it. The
    /// displayed percentage stays current to the hour while costing WidgetKit a single refresh per
    /// day, comfortably inside its budget. Recomputing on every wake would buy nothing: the Moon
    /// does not move fast enough to justify it.
    func getTimeline(in context: Context, completion: @escaping (Timeline<MoonEntry>) -> Void) {
        let start = Date.now
        let entries = (0..<24).map { Self.entry(at: start.addingTimeInterval(Double($0) * 3600)) }
        completion(Timeline(entries: entries,
                            policy: .after(start.addingTimeInterval(24 * 3600))))
    }

    static func entry(at date: Date) -> MoonEntry {
        MoonEntry(date: date, moon: MoonPhases.snapshot(at: date))
    }
}

// MARK: - Vocabulary

extension MoonPhases.Phase {
    /// Localized in *this* extension's bundle. A widget extension resolves a `LocalizedStringKey`
    /// against its own bundle, not the app's — which is why the watch complications settled for
    /// English `Text(verbatim:)`. This target carries its own catalog instead.
    var widgetName: LocalizedStringKey {
        switch self {
        case .new:          "New Moon"
        case .firstQuarter: "First Quarter"
        case .full:         "Full Moon"
        case .lastQuarter:  "Last Quarter"
        }
    }
}

// MARK: - View

struct MoonPhaseView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MoonEntry

    private var waxingWord: LocalizedStringKey { entry.moon.waxing ? "Waxing" : "Waning" }

    /// The already-formatted percentage, substituted as a *string*.
    ///
    /// Interpolating the `Int` and writing a literal `%` after it would put that percent sign into
    /// the catalog key — `Waxing %lld%` — where it reads as a malformed format specifier and is one
    /// stray character away from a crash at substitution time. Keeping the sign inside the value
    /// leaves the key as plain `Waxing %@`.
    private var pct: String { "\(entry.moon.percent)%" }

    /// One key per direction rather than a nested `Text` inside another `LocalizedStringKey`.
    /// Nesting yields the key `%@ %@`, which hands a translator two bare placeholders and no way to
    /// tell which is which — and several of these sixteen languages put the number first.
    private var stateLine: LocalizedStringKey {
        entry.moon.waxing ? "Waxing \(pct)" : "Waning \(pct)"
    }

    /// "Full in 4 d", or the new moon when that comes first. `soonest` picks between them in the
    /// Kit so this view holds no date arithmetic of its own.
    @ViewBuilder private var nextLine: some View {
        if let s = entry.moon.soonest {
            switch s.phase {
            case .full: Text("Full in \(s.days) d")
            default:    Text("New in \(s.days) d")
            }
        }
    }

    var body: some View {
        switch family {
        #if os(iOS)
        case .accessoryInline:
            // One line, no glyph: the inline slot strips styling and sits beside the time.
            Text(stateLine)

        case .accessoryCircular:
            VStack(spacing: 0) {
                Text(verbatim: "☽").font(.system(size: 15))
                Text(verbatim: "\(entry.moon.percent)%").font(.system(size: 12, weight: .medium))
            }

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.moon.phase.widgetName).font(.caption2).foregroundStyle(.secondary)
                Text(stateLine).font(.headline)
                nextLine.font(.caption2).foregroundStyle(.secondary)
            }
        #endif

        case .systemMedium:
            HStack(spacing: 16) {
                glyphBlock
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.moon.phase.widgetName).font(.headline)
                    Text("\(pct) illuminated").font(.subheadline)
                        .foregroundStyle(.secondary)
                    nextLine.font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

        default:   // .systemSmall and anything new
            VStack(spacing: 6) {
                glyphBlock
                Text(entry.moon.phase.widgetName).font(.caption).bold()
                nextLine.font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var glyphBlock: some View {
        VStack(spacing: 2) {
            Text(verbatim: "☽").font(.system(size: 34))
            Text(verbatim: "\(entry.moon.percent)%").font(.title3).bold()
            Text(waxingWord).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Widget

struct MoonPhaseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "eph.moonphase.ios", provider: MoonProvider()) { entry in
            MoonPhaseView(entry: entry)
                // Without this the widget looks correct in Simulator and renders as a grey slab on
                // device. It cost a shipped build to learn once already.
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Moon Phase")
        .description("Current phase, how much is lit, and when the next full moon falls.")
        // macOS desktop widgets get the system families only; the accessory slots are a Lock Screen
        // and Standby concept that has no macOS equivalent.
        #if os(iOS)
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
        #else
        .supportedFamilies([.systemSmall, .systemMedium])
        #endif
    }
}
