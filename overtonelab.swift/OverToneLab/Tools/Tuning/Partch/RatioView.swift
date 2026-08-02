import SwiftUI

struct RatioView: View {
    @ObservedObject var vm: PartchTuningViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Analyse a ratio")
                Stepper("Numerator  \(vm.num)", value: $vm.num, in: 1...64)
                Stepper("Denominator  \(vm.den)", value: $vm.den, in: 1...64)
                ResultRow(label: "\(vm.num):\(vm.den)", value: "\(Fmt.f(vm.ratioCents, 1)) ¢", emphasis: true)
                ResultRow(label: "12-TET", value: "\(vm.ratioNearestSemitone) st  (\(Fmt.signed(vm.ratioEtDeviation, 1)) ¢)")
                ResultRow(label: "Tenney height", value: Fmt.f(vm.tenney, 2))
                Text("Tenney height = log₂(n·d): lower means simpler and more consonant.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
