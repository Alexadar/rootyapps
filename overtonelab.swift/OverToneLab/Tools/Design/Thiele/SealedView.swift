import SwiftUI

struct SealedView: View {
    @ObservedObject var vm: ThieleViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Closed box")
                NumberField(title: "Box volume Vb", value: $vm.vb, unit: "L", range: 0.1...10000)
                ResultRow(label: "Compliance ratio α", value: Fmt.f(vm.alpha, 2))
                ResultRow(label: "System Q  Qtc", value: Fmt.f(vm.qtc, 3), emphasis: true)
                ResultRow(label: "System resonance Fc", value: "\(Fmt.f(vm.fc, 1)) Hz")
                ResultRow(label: "−3 dB point F3", value: "\(Fmt.f(vm.f3, 1)) Hz", emphasis: true)
            }.glassCard()
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: "Design to a target Qtc")
                NumberField(title: "Target Qtc", value: $vm.targetQtc, unit: "", range: 0.2...5)
                ResultRow(label: "Required Vb", value: "\(Fmt.f(vm.vbForTarget, 1)) L", emphasis: true)
                Text("Qtc 0.707 = flat, 0.5 = maximally damped/transient-tight, >0.8 = warmer with a bump.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
