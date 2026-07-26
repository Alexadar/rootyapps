import SwiftUI

/// Stage 1 — pick a moment: date/time, ◄ ► step nav, time zone, orb factor.
struct MomentControls: View {
    @ObservedObject var vm: ChartViewModel
    /// Nudge step for the ◄ ► arrows (persisted). Hour / Day / Week.
    @AppStorage("dateStepSeconds") private var stepSeconds: Double = 86_400

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Moment")

            DatePicker("Date & time", selection: $vm.date)
                .labelsHidden()
                .datePickerStyle(.compact)

            // ◄ [step] ► — step the moment back/forward by the chosen amount.
            HStack(spacing: 10) {
                Button { vm.date = vm.date.addingTimeInterval(-stepSeconds) } label: {
                    Image(systemName: "chevron.left").frame(maxWidth: .infinity, minHeight: 22)
                }
                Menu {
                    Picker("Step", selection: $stepSeconds) {
                        Text("Hour").tag(3_600.0)
                        Text("Day").tag(86_400.0)
                        Text("Week").tag(604_800.0)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(stepLabel)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .frame(minWidth: 70)
                }
                Button { vm.date = vm.date.addingTimeInterval(stepSeconds) } label: {
                    Image(systemName: "chevron.right")
                        .fontWeight(vm.demoHighlight == .forward ? .bold : .regular)
                        .foregroundStyle(vm.demoHighlight == .forward ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity, minHeight: 22)
                        .background(vm.demoHighlight == .forward ? NebulaPalette.accent : Color.clear,
                                    in: .capsule)
                }
                .scaleEffect(vm.demoHighlight == .forward ? 0.9 : 1)
            }
            .buttonStyle(.bordered)
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: vm.demoHighlight)

            // Time zone — searchable, persisted to preferences.
            TimeZoneRow(timeZone: $vm.timeZone)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Orb factor").foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f×", vm.orbFactor)).monospacedDigit()
                        .foregroundStyle(vm.demoHighlight == .orb ? NebulaPalette.accent : .primary)
                        .scaleEffect(vm.demoHighlight == .orb ? 1.28 : 1, anchor: .trailing)
                }
                Slider(value: $vm.orbFactor, in: 0.5...1.6, step: 0.1)
            }
            .padding(vm.demoHighlight == .orb ? 6 : 0)
            .background(vm.demoHighlight == .orb ? NebulaPalette.accent.opacity(0.12) : .clear,
                        in: .rect(cornerRadius: 10))
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: vm.demoHighlight)
        }
        .glassCard()
    }

    private var stepLabel: String {
        switch stepSeconds {
        case 3_600:   return "Hour"
        case 604_800: return "Week"
        default:      return "Day"
        }
    }
}
