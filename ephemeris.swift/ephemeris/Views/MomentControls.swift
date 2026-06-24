import SwiftUI

/// Stage 1 — pick a moment: date/time, UTC offset, orb factor.
struct MomentControls: View {
    @ObservedObject var vm: ChartViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Moment")

            DatePicker("Date & time", selection: $vm.date)
                .labelsHidden()
                .datePickerStyle(.compact)

            HStack {
                Text("UTC offset")
                    .foregroundStyle(.secondary)
                Spacer()
                Stepper(value: $vm.utcOffsetHours, in: -12...14, step: 0.5) {
                    Text(offsetLabel).monospacedDigit()
                }
                .fixedSize()
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Orb factor").foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f×", vm.orbFactor)).monospacedDigit()
                }
                Slider(value: $vm.orbFactor, in: 0.5...1.6, step: 0.1)
            }

            Button {
                vm.recompute()
            } label: {
                Label("Compute", systemImage: "sparkles").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
        }
        .glassCard()
        .onChange(of: vm.date) { _, _ in vm.recompute() }
        .onChange(of: vm.utcOffsetHours) { _, _ in vm.recompute() }
        .onChange(of: vm.orbFactor) { _, _ in vm.recompute() }
    }

    private var offsetLabel: String {
        let h = vm.utcOffsetHours
        let sign = h < 0 ? "−" : "+"
        let whole = Int(abs(h))
        let half = abs(h) - Double(whole) >= 0.25 ? "30" : "00"
        return "UTC\(sign)\(whole):\(half)"
    }
}
