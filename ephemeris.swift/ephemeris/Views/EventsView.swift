import SwiftUI
import EphemerisKit

/// The unified dated timeline: ingresses, lunations, stations, conjunctions and
/// mundane planet↔planet aspects around the chosen moment.
struct EventsView: View {
    let events: [AstroEvent]
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Events", trailing: Text(events.count, format: .number))
            if events.isEmpty {
                Text("No events in this window.").font(.callout).foregroundStyle(NebulaPalette.textSecondary)
            } else {
                // LAZY: the shipped 150-day window holds ~104 events, and a plain VStack lays out
                // and composites every one of them on each update — behind a glass material, which
                // is what made scrolling Cycles stutter on device. A LazyVStack builds only what is
                // near the viewport. It works here because this card is already inside the page's
                // ScrollView, which is what gives a lazy stack its geometry.
                LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(events, id: \.self) { e in
                    HStack(spacing: 12) {
                        Text(e.glyph)   // moon phases stay color emoji; sign/planet glyphs monochrome
                            .font(.headline)
                            .frame(width: 30, height: 30)
                            .background(NebulaPalette.accent.opacity(0.15), in: .circle)
                        VStack(alignment: .leading, spacing: 2) {
                            EventLabel.text(for: e).font(.callout)
                            HStack(spacing: 6) {
                                Text(EventLabel.className(for: e)).foregroundStyle(NebulaPalette.accent)
                                if e.retroA || e.retroB {
                                    Text(verbatim: "℞").foregroundStyle(NebulaPalette.retrograde)
                                }
                                Text(verbatim: "#\(e.code)").foregroundStyle(NebulaPalette.textFaint)
                            }
                            .font(.caption2)
                        }
                        Spacer()
                        Text(e.date, format: .dateTime.day().month(.abbreviated).year())
                            .font(.caption).monospacedDigit()
                            .foregroundStyle(Calendar.current.isDate(e.date, inSameDayAs: now)
                                             ? NebulaPalette.textPrimary : NebulaPalette.textSecondary)
                            // `code` is the Kit's stable event code, so this key does not move when
                            // the window shifts or the label is translated.
                            .accessibilityIdentifier("event.\(e.code).date")
                    }
                }
                }
            }
        }
        // Nebula dense glass card (material stack, not .glassEffect) — backs this long
        // overflowing list reliably.
        .nebulaCard(dense: true)
        // This list overflows the screen, and neither platform publishes content that has never
        // been on screen — so `.contain` here is what keeps the visible rows addressable at all.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card.events")
    }
}
