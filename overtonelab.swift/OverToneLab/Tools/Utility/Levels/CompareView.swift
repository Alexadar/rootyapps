import SwiftUI

struct CompareView: View {
    @ObservedObject var vm: LevelsViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Compare two levels")
                Picker("Quantity", selection: $vm.powerMode) {
                    Text("Voltage").tag(false); Text("Power").tag(true)
                }.pickerStyle(.segmented)
                NumberField(title: "Reference", value: $vm.valA, unit: vm.powerMode ? "W" : "V", range: 0.0001...1000000)
                NumberField(title: "Measured", value: $vm.valB, unit: vm.powerMode ? "W" : "V", range: 0.0001...1000000)
                ResultRow(label: "Difference", value: "\(Fmt.signed(vm.diffDB, 2)) dB", emphasis: true)
                Text(vm.powerMode ? "Power: 10·log₁₀(P₂/P₁) — ×2 = +3 dB."
                                  : "Voltage: 20·log₁₀(V₂/V₁) — ×2 = +6 dB.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
