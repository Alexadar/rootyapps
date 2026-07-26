import SwiftUI

struct WeightingView: View {
    @ObservedObject var vm: WeightingViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Frequency")
                NumberField(title: "Frequency", value: $vm.freq, unit: "Hz", range: 1...20000)
                ResultRow(label: "A-weighting", value: "\(Fmt.f(vm.aWeight, 2)) dB", emphasis: true)
                ResultRow(label: "C-weighting", value: "\(Fmt.f(vm.cWeight, 2)) dB")
                ResultRow(label: "Z-weighting", value: "\(Fmt.f(vm.zWeight, 1)) dB")
            }.glassCard()
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(title: "A-weighting by octave band")
                ForEach(vm.bandTable, id: \.hz) { b in
                    HStack {
                        Text(b.hz >= 1000 ? "\(Fmt.f(b.hz/1000, b.hz == 31500 ? 1 : 0)) kHz" : "\(Fmt.f(b.hz, b.hz < 100 ? 1 : 0)) Hz")
                            .foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
                        Spacer()
                        Text("\(Fmt.f(b.a, 1)) dB").monospacedDigit()
                    }.font(.callout)
                }
            }.glassCard()
        }
    }
}
