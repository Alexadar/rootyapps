import SwiftUI

struct PortedView: View {
    @ObservedObject var vm: ThieleViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Vented box tuning")
                NumberField(title: "Box volume Vb", value: $vm.vbPorted, unit: "L", range: 0.1...10000)
                NumberField(title: "Tuning Fb", value: $vm.fb, unit: "Hz", range: 1...300)
                NumberField(title: "Port diameter", value: $vm.portDiaCm, unit: "cm", range: 0.5...100)
                Stepper("Ports  \(vm.portCount)", value: $vm.portCount, in: 1...4)
            }.glassCard()
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(title: "Port")
                if vm.portFits {
                    ResultRow(label: "Length each", value: "\(Fmt.f(vm.portLenCm, 1)) cm", emphasis: true)
                    Text("Includes the port end correction. Wider ports run quieter but need more length; if the tube won't fit the box, add ports or a slot.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ResultRow(label: "Length each", value: "— too short", emphasis: true)
                    Text("At this diameter the required length is negative — the port would be a plain hole. Use a smaller diameter, a lower Fb, or a larger box.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.glassCard()
        }
    }
}
