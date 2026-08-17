import SwiftUI
import GenerationKit

/// The six parts of the model, checked off as the Neural Engine finishes each one.
///
/// ### Why a checklist and not a bar
///
/// A bar needs a fraction, and there is no honest fraction inside a single compile — Core ML reports
/// nothing between "started" and "finished". What *is* real is how many of the six have landed, so
/// that is what is shown. The one thing nobody can count — the seconds inside the part being worked
/// on — carries a small arc instead. A bar there would be inventing the only number nobody has.
///
/// Sizes are board `6a`: heading 16, count 14, rows 14.5, card radius 28.
struct TuningChecklist: View {

    @MainActor
    @Observable
    final class State {
        enum Row: Equatable { case waiting, working, ready }

        private(set) var parts: [ModelPart] = []
        private(set) var rows: [String: Row] = [:]

        var completedCount: Int { rows.values.filter { $0 == .ready }.count }
        var total: Int { parts.count }
        var isFinished: Bool { total > 0 && completedCount >= total }

        func begin(parts: [ModelPart], alreadyCompiled: Set<String>) {
            self.parts = parts
            rows = Dictionary(uniqueKeysWithValues: parts.map {
                ($0.id, alreadyCompiled.contains($0.id) ? Row.ready : .waiting)
            })
        }

        func absorb(_ event: TuningEvent) {
            switch event {
            case .began(let part, _, _):
                rows[part.id] = .working
            case .finished(let part, _, _, _):
                rows[part.id] = .ready
            case .failed(let part, _):
                // Not an error row. A graph that will not compile still runs, on the CPU, slower —
                // so it is finished as far as this list is concerned. A red row would alarm the user
                // about something they cannot act on, and would stall the counter for ever.
                rows[part.id] = .ready
            case .stoodDown:
                for (id, row) in rows where row == .working { rows[id] = .waiting }
            }
        }

        func row(for part: ModelPart) -> Row { rows[part.id] ?? .waiting }
    }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.wpAccessibility) private var accessibility

    var state: State

    var body: some View {
        VStack(alignment: .leading, spacing: WP.Space.grid) {
            HStack(alignment: .firstTextBaseline) {
                Text("Preparing the model")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WP.ink(scheme))
                Spacer()
                Text("\(state.completedCount) of \(state.total) parts")
                    .font(.system(size: 14).monospacedDigit())
                    .foregroundStyle(WP.ink3(scheme))
            }

            VStack(alignment: .leading, spacing: WP.Space.gap) {
                ForEach(state.parts) { part in
                    row(part, state: state.row(for: part))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WP.Space.margin)
        .wpGlassCard()
        .animation(WPMotion.morph(reduceMotion: accessibility.reduceMotion), value: state.rows)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func row(_ part: ModelPart, state row: State.Row) -> some View {
        HStack(spacing: WP.Space.gap) {
            marker(row)
                .frame(width: 24, height: 24)
            Text(part.name)
                .font(.system(size: 14.5, weight: row == .working ? .semibold : .regular))
                .foregroundStyle(row == .waiting ? WP.ink3(scheme) : WP.ink(scheme))
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(part.name), \(word(for: row))")
    }

    @ViewBuilder
    private func marker(_ row: State.Row) -> some View {
        switch row {
        case .ready:
            Image(systemName: "checkmark.circle")
                .font(.system(size: 21))
                .foregroundStyle(WP.success(scheme))
                .transition(.opacity)
        case .working:
            BreathingArc(side: 21)
        case .waiting:
            Circle()
                .strokeBorder(WP.ink3(scheme).opacity(0.3), lineWidth: 1.5)
        }
    }

    /// State in words as well as in shape — `BreathingArc` holds still under Reduce Motion, which
    /// would make "working" and "waiting" identical to look at, and the house rule is that state is
    /// never carried by shape or colour alone. Spoken by VoiceOver rather than drawn, so the card
    /// keeps the design's clean three-column look.
    private func word(for row: State.Row) -> String {
        switch row {
        case .ready: return "ready"
        case .working: return "working now"
        case .waiting: return "waiting"
        }
    }
}
