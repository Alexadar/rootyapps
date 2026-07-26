import SwiftUI

struct CompressorGainView: View {
    @ObservedObject var vm: CompressorViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Gain computer")
                NumberField(title: "Input level", value: $vm.input, unit: "dBFS", range: -60...0)
                NumberField(title: "Threshold", value: $vm.threshold, unit: "dBFS", range: -60...0)
                NumberField(title: "Ratio", value: $vm.ratio, unit: ":1", range: 1...100)
                NumberField(title: "Knee width", value: $vm.knee, unit: "dB", range: 0...24)
                NumberField(title: "Makeup gain", value: $vm.makeup, unit: "dB", range: 0...24)
                ResultRow(label: "Gain reduction", value: "\(Fmt.f(vm.gainReduction, 1)) dB", emphasis: true)
                ResultRow(label: "Output level", value: "\(Fmt.signed(vm.output, 1)) dBFS")
                ResultRow(label: "Effective ratio",
                          value: vm.effRatio.isInfinite ? "∞ : 1" : "\(Fmt.f(vm.effRatio, 1)) : 1")
            }.glassCard()
        }
    }
}
