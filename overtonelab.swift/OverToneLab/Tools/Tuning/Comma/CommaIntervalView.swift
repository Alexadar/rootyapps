import SwiftUI

struct CommaIntervalView: View {
    @ObservedObject var vm: CommaTuningViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Ratio → cents")
                HStack {
                    NumberField(title: "Numerator", value: $vm.ratioNum, range: 1...9999)
                    NumberField(title: "Denominator", value: $vm.ratioDen, range: 1...9999)
                }
                ResultRow(label: "Interval", value: "\(Fmt.f(vm.ratioCents, 3)) ¢", emphasis: true)
            }.glassCard()

            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Cents → ratio")
                NumberField(title: "Cents", value: $vm.centsInput, unit: "¢", range: -12000...12000)
                ResultRow(label: "Frequency ratio", value: Fmt.f(vm.centsAsRatio, 6), emphasis: true)
            }.glassCard()
        }
    }
}
