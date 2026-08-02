import SwiftUI

struct TensionView: View {
    @ObservedObject var vm: StringsViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "String")
                NumberField(title: "Pitch", value: $vm.freq, unit: "Hz", range: 1...20000)
                NumberField(title: "Vibrating length", value: $vm.lengthM, unit: "m", range: 0.01...5)
                NumberField(title: "Linear density", value: $vm.mu, unit: "kg/m", range: 0.0001...1)
            }.glassCard()
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Tension (Mersenne's law)")
                ResultRow(label: "Tension", value: "\(Fmt.f(vm.tensionN, 2)) N", emphasis: true, id: "result.mersenne")
                ResultRow(label: "Tension", value: "\(Fmt.f(vm.tensionLbf, 2)) lbf")
            }.glassCard()
        }
    }
}
