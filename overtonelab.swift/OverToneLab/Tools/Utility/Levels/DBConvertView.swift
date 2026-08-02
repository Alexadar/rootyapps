import SwiftUI

struct DBConvertView: View {
    @ObservedObject var vm: LevelsViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Voltage → dB")
                NumberField(title: "Voltage (RMS)", value: $vm.volts, unit: "V", range: 0.0001...100000)
                ResultRow(label: "dBu", value: "\(Fmt.f(vm.dBu, 2)) dBu", emphasis: true, id: "result.levels")
                ResultRow(label: "dBV", value: "\(Fmt.f(vm.dBV, 2)) dBV")
                Text("0 dBu = 0.7746 V (√(1 mW into 600 Ω)); 0 dBV = 1 V. They differ by 2.2 dB.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
