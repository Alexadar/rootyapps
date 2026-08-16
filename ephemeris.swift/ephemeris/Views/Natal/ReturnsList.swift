import SwiftUI
import EphemerisKit

/// When a body comes back to where it was at birth.
///
/// A list rather than a ring, because choosing *which* return is the question — once chosen, the
/// chart itself renders through the shared readout like everything else.
///
/// Returns are the one practitioner feature that needs an exact moment. A solar return is cast for
/// the instant the Sun regains its natal degree, and that instant is only as good as the birth
/// degree it targets — so an untimed chart gets an explanation here, not a list of plausible dates.
struct ReturnsList: View {
    let facets: ChartFacets
    @Binding var selected: ReturnEvent?
    var onOpen: (ReturnEvent) -> Void
    /// Present on the phone, where a chart can be handed to the watch. Nil elsewhere, so the Mac
    /// does not offer to configure a device it cannot reach.
    var watchDefault: (isDefault: Bool, toggle: () -> Void)? = nil

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Returns")

            if !facets.chart.isTimeKnown {
                HonestStateCard(
                    title: L.string("Returns need an exact moment", locale: locale),
                    explanation: L.string(
                        "A return is cast for the instant a body regains its natal degree. Without a birth time that degree is uncertain by up to a day's motion, and the return chart with it.",
                        locale: locale),
                    fixLabel: L.string("Add a birth time", locale: locale))
            } else {
                let events = facets.returnCycles()
                if events.isEmpty {
                    Text("No return falls inside the verified window.")
                        .font(.callout)
                        .foregroundStyle(NebulaPalette.textSecondary)
                }
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    row(event, isNext: index == 0)
                    if event.id != events.last?.id { NebulaPalette.divider.frame(height: 0.75) }
                }

                // The watch has no chart library — it cannot browse, so one chart is nominated
                // here. Offered beside Returns because the Returns row is the only thing it feeds.
                if let watchDefault {
                    NebulaPalette.divider.frame(height: 0.75)
                    Button(action: watchDefault.toggle) {
                        HStack(spacing: 8) {
                            Image(systemName: watchDefault.isDefault
                                  ? "applewatch.watchface" : "applewatch")
                            Text(watchDefault.isDefault
                                 ? "Showing on your watch"
                                 : "Show this chart's return on your watch")
                            Spacer()
                        }
                        .font(.caption)
                        .foregroundStyle(watchDefault.isDefault
                                         ? NebulaPalette.accent : NebulaPalette.accentCyan)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("returns.watchDefault")
                }
            }
        }
        .glassCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(NebulaPractitioner.A11y.returnsList)
    }

    private func row(_ event: ReturnEvent, isNext: Bool) -> some View {
        let verified = facets.isWithinVerifiedWindow(event.date)
        return Button {
            guard verified else { return }
            onOpen(event)
        } label: {
            HStack(spacing: 10) {
                Text(verbatim: event.body.glyph)
                    .foregroundStyle(NebulaPractitioner.outerRingGlyph)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(L.loc(event.body.name))
                        if isNext {
                            Text("NEXT")
                                .font(NebulaPractitioner.rangeTagFont)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(NebulaPalette.accent.opacity(0.18), in: .rect(cornerRadius: 3))
                                .foregroundStyle(NebulaPalette.accent)
                        }
                        if event.retrograde {
                            Text(verbatim: "℞").foregroundStyle(NebulaPalette.retrograde)
                        }
                    }
                    Text(event.date, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                        .font(.caption)
                        .foregroundStyle(NebulaPalette.textSecondary)
                    // The row stays when the date is outside what the ephemeris is verified
                    // across — disabled and saying so. Hiding it would answer "when is my next
                    // Saturn return" with silence, which reads as "there isn't one".
                    if !verified {
                        Text(verbatim: String(
                            format: L.string("Outside the verified range %1$d–%2$d", locale: locale),
                            NebulaPractitioner.ephemerisWindow.lowerBound,
                            NebulaPractitioner.ephemerisWindow.upperBound))
                            .font(.caption2)
                            .foregroundStyle(NebulaPractitioner.warn)
                    }
                }
                Spacer()
                SignChip(glyph: event.sign.glyph, size: 20)
            }
            .font(.callout)
            .contentShape(.rect)
            .opacity(verified ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!verified)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("\(NebulaPractitioner.A11y.returnsRow).\(event.body.rawValue)")
    }
}
