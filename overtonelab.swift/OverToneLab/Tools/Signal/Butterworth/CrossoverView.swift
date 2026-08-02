import SwiftUI

struct CrossoverView: View {
    @ObservedObject var vm: FilterViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Linkwitz-Riley crossover")
                Picker("Order", selection: $vm.lrHalf) {
                    Text("LR2").tag(1); Text("LR4").tag(2); Text("LR8").tag(4)
                }.pickerStyle(.segmented)
                NumberField(title: "Crossover fc", value: $vm.xoverHz, unit: "Hz", range: 1...100000)
                ResultRow(label: "Each branch @ fc", value: "\(Fmt.f(vm.lrBranchAtFcDB, 2)) dB", emphasis: true)
                ResultRow(label: "Slope", value: "\(Int(vm.lrSlopeDbOct)) dB/oct")
                ResultRow(label: "One octave into stopband", value: "\(Fmt.f(vm.lrOctaveAwayDB, 1)) dB")
                Text("\(vm.lrName): both branches −6 dB at fc, in phase, summing flat.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
