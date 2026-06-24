import SwiftUI
import EphemerisKit

/// The unified dated timeline: ingresses, lunations, stations, conjunctions and
/// mundane planet↔planet aspects around the chosen moment.
struct EventsView: View {
    let events: [AstroEvent]
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Events", trailing: "\(events.count)")
            if events.isEmpty {
                Text("No events in this window.").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(events, id: \.self) { e in
                    HStack(spacing: 12) {
                        Text(e.glyph)
                            .font(.headline)
                            .frame(width: 30, height: 30)
                            .background(.tint.opacity(0.15), in: .circle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.label()).font(.callout)
                            HStack(spacing: 6) {
                                Text(e.eventClass.rawValue).foregroundStyle(.tint)
                                if e.retroA || e.retroB {
                                    Text("℞").foregroundStyle(Color(rgbHex: 0xe67e22))
                                }
                                Text("#\(e.code)").foregroundStyle(.tertiary)
                            }
                            .font(.caption2)
                        }
                        Spacer()
                        Text(e.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption).monospacedDigit()
                            .foregroundStyle(Calendar.current.isDate(e.date, inSameDayAs: now) ? .primary : .secondary)
                    }
                }
            }
        }
        .glassCard()
    }
}
