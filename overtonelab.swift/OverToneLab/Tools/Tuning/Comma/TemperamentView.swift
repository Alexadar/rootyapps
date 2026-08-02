import SwiftUI

struct TemperamentView: View {
    @ObservedObject var vm: CommaTuningViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "The perfect fifth")
                ResultRow(label: "Just (3:2)", value: "\(Fmt.f(vm.justFifth, 3)) ¢", emphasis: true)
                ResultRow(label: "¼-comma meantone", value: "\(Fmt.f(vm.meantoneFifth, 3)) ¢", emphasis: true)
                ResultRow(label: "12-EDO", value: "700.000 ¢")
            }.glassCard()

            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Commas")
                ResultRow(label: "Syntonic (81:80)", value: "\(Fmt.f(vm.syntonicComma, 3)) ¢", emphasis: true)
                ResultRow(label: "Pythagorean", value: "\(Fmt.f(vm.pythagoreanComma, 3)) ¢", emphasis: true)
                Text("The comma is the small gap that no single tuning can close — the reason temperaments exist.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
