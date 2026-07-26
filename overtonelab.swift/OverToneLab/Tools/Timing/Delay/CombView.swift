import SwiftUI

struct CombView: View {
    @ObservedObject var vm: DelayViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Comb filtering")
                NumberField(title: "Delay", value: $vm.combDelayMs, unit: "ms", range: 0.001...100_000)
                ResultRow(label: "First notch", value: "\(Fmt.f(vm.combNullHz, 1)) Hz", emphasis: true)
                Text("Summing a signal with a delayed copy cancels at f = 1/(2·t), then every odd multiple — the tell-tale comb of a mistimed mic or reflection.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
