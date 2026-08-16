import SwiftUI
import EphemerisKit

/// Upcoming ingresses, lunations, stations and aspects, each with a real date.
///
/// This is the screen that makes the app read as an almanac rather than a horoscope: every row is
/// a dated fact computed from the ephemeris, not a characterisation. It needs no observer
/// position — all of it is geocentric — so it works on a watch that has never synced.
///
/// Sentences are rebuilt from pattern keys rather than localizing `AstroEvent.label()`, which the
/// Kit composes combinatorially in English and therefore can never be a catalog key. The phone
/// learned this the hard way; the watch inherits the fix instead of the bug.
struct WatchEventsView: View {
    let date: Date

    private var events: [AstroEvent] {
        let window = DateInterval(start: date, end: date.addingTimeInterval(120 * 86_400))
        return Array(EventTimeline.allEvents(in: window).filter { $0.date >= date }.prefix(40))
    }

    /// The next return for the default chart set on the phone, or nil when none is set.
    ///
    /// This is the *only* one of the seven practitioner features that reaches the watch. The others
    /// — synastry, composite, progressions, dignities, chart analysis, midpoints — are consultation
    /// tools: multi-chart or table-shaped, and every one fails the test this row passes, which is
    /// "does the value change, and would you glance at it more than once a day?". A synastry grid
    /// at 176pt is the aspects list the watch already dropped.
    ///
    /// Computed here rather than sent across: the watch has the whole Kit, so a birth instant is
    /// enough. Shipping the return *date* would be a snapshot that goes stale the moment it passes.
    private var nextReturn: (event: ReturnEvent, chartName: String)? {
        guard let chart = SharedStore().defaultChart else { return nil }
        let natalSun = Ephemeris.longitude(of: .sun, at: chart.instant)
        guard let event = Returns.next(.sun, to: natalSun, after: date) else { return nil }
        return (event, chart.name)
    }

    var body: some View {
        List {
                // Present only when a default chart is set. With none, the row is simply absent —
                // a placeholder would invite a tap that leads nowhere on a device with no library.
                if let next = nextReturn {
                    HStack(spacing: 8) {
                        Text(verbatim: next.event.body.glyph + "\u{FE0E}")
                            .frame(width: 18)
                            .foregroundStyle(Color.pink)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: next.chartName + " · " + L.string("Return", locale: .current))
                                .font(.caption2).lineLimit(1)
                            Text(next.event.date,
                                 format: .dateTime.day().month(.abbreviated).hour().minute())
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("watch.returnRow")
                }

                if events.isEmpty {
                    Text(L.loc("No events in this window.")).font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(events.enumerated()), id: \.offset) { _, e in
                        HStack(spacing: 8) {
                            Text(verbatim: e.glyph + "\u{FE0E}")
                                .frame(width: 18)
                                .foregroundStyle(e.retroA || e.retroB ? Color.orange : Color.primary)
                            VStack(alignment: .leading, spacing: 1) {
                                WatchEventLabel.text(for: e).font(.caption2).lineLimit(2)
                                Text(e.date, format: .dateTime.day().month(.abbreviated))
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
        }
        .scrollContentBackground(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("watch.events")
    }
}

/// Translated display text for an event, composed from pattern keys.
///
/// A direct copy of the phone's approach and deliberately so: `AstroEvent.label()` builds ~1,300
/// English sentences combinatorially, so no individual label can be a localization key. Feeding
/// one to `L.loc` returns the English unchanged — which renders fine and is simply wrong.
enum WatchEventLabel {
    static func text(for e: AstroEvent) -> Text {
        let body = Text(L.loc(e.bodyA.name))
        let sign = Text(L.loc(e.sign?.name ?? ""))
        switch e.kind {
        case .signIngress:            return Text("\(body) enters \(sign)")
        case .newMoon:                return Text("New Moon in \(sign)")
        case .fullMoon:               return Text("Full Moon in \(sign)")
        case .stationRetrograde:      return Text("\(body) stations retrograde")
        case .stationDirect:          return Text("\(body) stations direct")
        case .inferiorConjunction:    return Text("\(body) inferior conjunction")
        case .superiorConjunction:    return Text("\(body) superior conjunction")
        case .greatestElongationEast: return Text("\(body) greatest elongation east")
        case .greatestElongationWest: return Text("\(body) greatest elongation west")
        case .conjunction:            return Text("\(body) conjunction Sun")
        case .opposition:             return Text("\(body) opposition Sun")
        case .mundaneAspect:
            let other = Text(L.loc((e.bodyB ?? e.bodyA).name))
            let aspect = Text(L.loc(e.aspect?.name ?? ""))
            return Text("\(body) \(aspect) \(other)")
        }
    }
}
