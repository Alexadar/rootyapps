import SwiftUI

struct SummationView: View {
    @ObservedObject var vm: SPLViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Two sources")
                NumberField(title: "Source A", value: $vm.la, unit: "dB", range: 0...200)
                NumberField(title: "Source B", value: $vm.lb, unit: "dB", range: 0...200)
                ResultRow(label: "Combined (incoherent)", value: "\(Fmt.f(vm.sumTwo, 1)) dB", emphasis: true)
                Text("Two equal uncorrelated sources add +3 dB; 10 dB apart adds only ~0.4 dB.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "N equal sources")
                NumberField(title: "Each source", value: $vm.level, unit: "dB", range: 0...200)
                Stepper("Count  \(vm.count)", value: $vm.count, in: 1...64)
                ResultRow(label: "Incoherent", value: "\(Fmt.f(vm.incN, 1)) dB", emphasis: true)
                ResultRow(label: "Coherent", value: "\(Fmt.f(vm.cohN, 1)) dB")
                Text("Uncorrelated: +10·log₁₀(N). In-phase (coherent): +20·log₁₀(N).")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
