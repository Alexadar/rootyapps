import SwiftUI

struct InterferenceTwoSourceView: View {
    @ObservedObject var vm: InterferenceViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Two coherent sources")
                NumberField(title: "Path difference", value: $vm.pathDiff, unit: "m", range: 0.01...50)
                NumberField(title: "Speed of sound", value: $vm.speed, unit: "m/s", range: 330...350)
                ResultRow(label: "First null", value: "\(Fmt.f(vm.combFirstNull, 1)) Hz", emphasis: true)
                ResultRow(label: "Comb spacing", value: "\(Fmt.f(vm.combSpacing, 1)) Hz")
                ResultRow(label: "Arrival delay", value: "\(Fmt.f(vm.delayMs, 2)) ms")
            }.glassCard()

            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: "Nulls (Hz)")
                ForEach(Array(vm.combNulls.enumerated()), id: \.offset) { i, f in
                    HStack {
                        Text("Null \(i + 1)").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Fmt.f(f, 1)) Hz").monospacedDigit().foregroundStyle(OTL.textPrimary)
                    }.font(.callout)
                }
            }.glassCard()
        }
    }
}
