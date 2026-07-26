import SwiftUI

struct RCView: View {
    @ObservedObject var vm: PassiveViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "RC filter")
                NumberField(title: "Resistance", value: $vm.rcR, unit: "kΩ", range: 0.001...100000)
                NumberField(title: "Capacitance", value: $vm.rcC, unit: "µF", range: 0.0001...100000)
                ResultRow(label: "Corner (−3 dB)", value: "\(Fmt.f(vm.rcHz, 2)) Hz", emphasis: true)
                Text("f = 1/(2π·R·C). 1 kΩ + 1 µF ≈ 159 Hz.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "RL filter")
                NumberField(title: "Resistance", value: $vm.rlR, unit: "kΩ", range: 0.001...100000)
                NumberField(title: "Inductance", value: $vm.rlL, unit: "mH", range: 0.001...100000)
                ResultRow(label: "Corner (−3 dB)", value: "\(Fmt.f(vm.rlHz, 1)) Hz", emphasis: true)
                Text("f = R/(2π·L).")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
