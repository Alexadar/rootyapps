import SwiftUI

struct EDOView: View {
    @ObservedObject var vm: CommaTuningViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Equal division of the octave")
                NumberField(title: "Divisions (EDO)", value: $vm.edoN, range: 1...240)
                ResultRow(label: "Step size", value: "\(Fmt.f(vm.edoStepSize, 3)) ¢", emphasis: true)
            }.glassCard()

            VStack(alignment: .leading, spacing: 8) {
                CardHeader(title: "Degrees (cents)")
                ForEach(Array(vm.edoSteps.enumerated()), id: \.offset) { i, c in
                    HStack {
                        Text("\(i + 1)").foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
                        Spacer()
                        Text("\(Fmt.f(c, 2)) ¢").monospacedDigit()
                    }.font(.callout)
                    if i < vm.edoSteps.count - 1 { Divider().overlay(.white.opacity(0.06)) }
                }
            }.glassCard()
        }
    }
}
