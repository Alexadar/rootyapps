import SwiftUI

struct CompressorTimeView: View {
    @ObservedObject var vm: CompressorViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Attack / release envelope")
                NumberField(title: "Rise time (10–90%)", value: $vm.time, unit: "ms", range: 0.01...5000)
                NumberField(title: "Sample rate", value: $vm.fs, unit: "Hz", range: 8000...768000)
                ResultRow(label: "Time constant τ", value: "\(Fmt.f(vm.tau, 3)) ms", emphasis: true)
                ResultRow(label: "One-pole coeff", value: Fmt.f(vm.coeff, 6))
                ResultRow(label: "Reached in rise time", value: Fmt.pct(vm.pctAtTime))
            }.glassCard()
        }
    }
}
