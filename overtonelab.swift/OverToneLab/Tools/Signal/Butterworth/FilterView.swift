import SwiftUI

struct FilterView: View {
    @ObservedObject var vm: FilterViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Butterworth low-pass")
                Stepper("Order  \(vm.order)  (\(Int(vm.slopeDbOct)) dB/oct)", value: $vm.order, in: 1...8)
                NumberField(title: "Cutoff fc", value: $vm.fcHz, unit: "Hz", range: 1...100000)
                NumberField(title: "Test frequency", value: $vm.testHz, unit: "Hz", range: 1...100000)
                ResultRow(label: "Magnitude", value: "\(Fmt.f(vm.magDB, 2)) dB", emphasis: true, id: "result.butterworth")
            }.glassCard()
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(title: "Response vs cutoff")
                ForEach(vm.response, id: \.label) { row in
                    HStack {
                        Text(row.label).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                        Spacer()
                        Text("\(Fmt.f(row.db, 2)) dB").monospacedDigit()
                    }.font(.callout)
                }
                Text("−3 dB at the cutoff by definition; asymptotic to \(Int(vm.slopeDbOct)) dB/octave.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
