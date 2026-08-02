import SwiftUI

struct DynamicRangeView: View {
    @ObservedObject var vm: LevelsViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Bit depth → dynamic range")
                Stepper("Bit depth  \(Int(vm.bits))", value: $vm.bits, in: 8...32, step: 1)
                ResultRow(label: "Dynamic range", value: "\(Fmt.f(vm.dynamicRange, 2)) dB", emphasis: true)
                Text("Theoretical full-scale-sine SNR = 6.02·N + 1.76 dB. 16-bit ≈ 98 dB, 24-bit ≈ 146 dB.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
