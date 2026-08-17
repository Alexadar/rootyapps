import SwiftUI
import MeasureKit

/// What the measurement found. One hero readout, the rest as ordinary rows.
///
/// **No target, no delta, no verdict** — see `MeasureView`. This screen reports; `benchmark` judges.
struct MeasureResultsView: View {
    let session: MeasurementStore.Session

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Measured", trailing: session.sourceName)

            // The hero is tempo when there is one, loudness otherwise: the biggest number on screen
            // should be the one the user most likely came for.
            if let bpm = session.bpm {
                ResultRow(label: "Tempo", value: Fmt.f(bpm, 1), unit: "BPM",
                          emphasis: true, id: "measure.bpm")
            } else if let lufs = session.integratedLUFS {
                ResultRow(label: "Integrated", value: Fmt.f(lufs, 1), unit: "LUFS",
                          emphasis: true, id: "measure.lufs")
            } else {
                ResultRow(label: "Tempo", value: "——", unit: "listening",
                          emphasis: true, id: "measure.bpm")
            }

            if session.bpm != nil, let lufs = session.integratedLUFS {
                ResultRow(label: "Integrated", value: Fmt.f(lufs, 1), unit: "LUFS", id: "measure.lufs")
            }
            if let peak = session.peakDB {
                ResultRow(label: "True peak", value: Fmt.signed(peak, 1), unit: "dBFS", id: "measure.peak")
            }
            if let key = session.keyName {
                ResultRow(label: "Key", value: key, id: "measure.key")
            }
            if let bars = session.barCount {
                ResultRow(label: "Bars", value: Fmt.count(Double(bars)), id: "measure.bars")
            }

            Text("\(session.sourceName) · \(session.measuredAt.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(OTL.textTertiary)
        }
        .glassCard()
    }
}

/// The routing table, as rows the user can act on.
///
/// Only tools that consume something in this session appear — a Send button for a tool that cannot
/// use the value would be a promise the app cannot keep. Tapping hands the value over **and marks it
/// measured**; the tool opens with the number already in its field, fully editable.
struct SendToToolsCard: View {
    let session: MeasurementStore.Session

    @EnvironmentObject private var store: MeasurementStore
    @EnvironmentObject private var provenance: FieldProvenance
    @EnvironmentObject private var handoff: MeasurementHandoff

    var body: some View {
        // Absent, not disabled: while BPM is still nil, tempo and delay simply are not offered.
        let tools = store.feedableTools
        if !tools.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: "Send to")
                ForEach(tools) { tool in
                    NavigationLink(value: tool) {
                        HStack(spacing: 10) {
                            Image(systemName: tool.symbol)
                                .foregroundStyle(tool.accent)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tool.title)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(OTL.textPrimary)
                                Text(handoff.summary(for: tool, session: session))
                                    .font(.caption)
                                    .foregroundStyle(OTL.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(OTL.textTertiary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("send.\(tool.rawValue)")
                    .simultaneousGesture(TapGesture().onEnded {
                        handoff.hand(session: session, to: tool, provenance: provenance)
                    })
                }
            }
            .glassCard()
        }
    }
}
