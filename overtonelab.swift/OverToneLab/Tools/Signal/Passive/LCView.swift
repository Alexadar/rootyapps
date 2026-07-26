import SwiftUI

struct LCView: View {
    @ObservedObject var vm: PassiveViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "LC resonance")
                NumberField(title: "Inductance", value: $vm.lcL, unit: "mH", range: 0.001...100000)
                NumberField(title: "Capacitance", value: $vm.lcC, unit: "µF", range: 0.0001...100000)
                ResultRow(label: "Resonant frequency", value: "\(Fmt.f(vm.lcHz, 1)) Hz", emphasis: true)
                Text("f = 1/(2π·√(L·C)). The tuned frequency of a passive LC crossover section or trap.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
