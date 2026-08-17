import SwiftUI
import MeasureKit

/// Audio Analysis — a **source**, not tool #27.
///
/// It measures, then hands values to the calculators that already own the reasoning. Every number it
/// produces lands in an ordinary input field and stays fully editable: measurement is a starting
/// point, never a lock.
///
/// **The `benchmark` boundary is the rule this screen is built around.** Analysis renders no target,
/// no delta and no verdict — it will happily tell you the programme is −18.3 LUFS and will never tell
/// you that is 4.3 too loud for Spotify. That single restriction is what stops LUFS existing in two
/// places, and it is why `AnalysisBoundaryChecks` asserts no such identifier exists here.
struct MeasureView: View {
    @EnvironmentObject private var store: MeasurementStore
    @EnvironmentObject private var provenance: FieldProvenance
    @Environment(\.dismiss) private var dismiss

    @State private var provider: AnalysisProvider?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                switch store.presence {
                case .none:    idleCard
                case .live:    liveCard
                case .complete: resultsCards
                }
                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(OTL.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard()
                }
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .padding()
        }
        .background(AppBackground(accent: OTL.measureAccent))
        .tint(OTL.measureAccent)
        .navigationTitle("Measure")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Idle

    private var idleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Measure audio")
            Text("Listen to what is playing and hand the numbers to the calculators. Everything it finds stays editable.")
                .font(.callout)
                .foregroundStyle(OTL.textSecondary)
            listenButton
        }
        .glassCard()
    }

    /// Microphone permission is requested **by this button**, never at launch. This app has never
    /// asked the user for anything; the first prompt should be attached to the thing they just chose
    /// to do.
    private var listenButton: some View {
        Button {
            Task { await listen() }
        } label: {
            Label("Listen", systemImage: "waveform.badge.mic")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("measure.listen")
    }

    // MARK: - Live

    private var liveCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Listening")
            // BPM is nil until two beats land. Never a zero, and never a spinner that lies about
            // having an answer — the em dashes say "not yet" in a way a 0 cannot.
            ResultRow(label: "Tempo",
                      value: store.session?.bpm.map { Fmt.f($0, 1) } ?? "——",
                      unit: store.session?.bpm == nil ? "listening" : "BPM",
                      emphasis: true,
                      id: "measure.bpm")
            if let lufs = store.session?.integratedLUFS {
                ResultRow(label: "Integrated", value: Fmt.f(lufs, 1), unit: "LUFS", id: "measure.lufs")
            }
            Button(role: .cancel) { stop() } label: {
                Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("measure.stop")
        }
        .glassCard()
    }

    // MARK: - Complete

    @ViewBuilder private var resultsCards: some View {
        if let session = store.session {
            MeasureResultsView(session: session)
            SendToToolsCard(session: session)
            Button {
                store.clear()
            } label: {
                Label("Measure again", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("measure.again")
        }
    }

    // MARK: - Capture

    private func listen() async {
        error = nil
        guard let p = AnalysisProviderFactory.make() else {
            error = AnalysisProviderError.unavailable.errorDescription
            return
        }
        provider = p
        store.beginLive(sourceName: p.sourceName)
        do {
            try await p.start { session in
                MainActor.assumeIsolated { store.update { $0 = session } }
            }
            store.finish(store.session ?? MeasurementStore.Session(sourceName: p.sourceName,
                                                                  measuredAt: Date()))
        } catch {
            store.clear()
            self.error = error.localizedDescription
        }
    }

    private func stop() {
        provider?.stop()
        if let s = store.session { store.finish(s) }
    }
}
