import SwiftUI
import BiquadKit

struct BiquadDesignView: View {
    @ObservedObject var vm: BiquadViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Filter")
                Picker("Type", selection: $vm.kind) {
                    ForEach(Biquad.Kind.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                NumberField(title: "Sample rate", value: $vm.fs, unit: "Hz", range: 8000...768000)
                NumberField(title: "Frequency f₀", value: $vm.f0, unit: "Hz", range: 20...384000)
                NumberField(title: "Q", value: $vm.q, range: 0.1...40)
                if vm.kind.usesGain {
                    NumberField(title: "Gain", value: $vm.gainDB, unit: "dB", range: -24...24)
                }
                ResultRow(label: "Magnitude @ f₀", value: "\(Fmt.signed(vm.magAtF0, 2)) dB", emphasis: true)
            }.glassCard()

            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Probe")
                NumberField(title: "Probe frequency", value: $vm.probe, unit: "Hz", range: 20...384000)
                ResultRow(label: "Magnitude", value: "\(Fmt.signed(vm.magAtProbe, 2)) dB")
            }.glassCard()

            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: "Coefficients (a₀-normalized)")
                ResultRow(label: "b0", value: Fmt.f(vm.coeffs.b0, 6))
                ResultRow(label: "b1", value: Fmt.f(vm.coeffs.b1, 6))
                ResultRow(label: "b2", value: Fmt.f(vm.coeffs.b2, 6))
                ResultRow(label: "a1", value: Fmt.f(vm.coeffs.a1, 6))
                ResultRow(label: "a2", value: Fmt.f(vm.coeffs.a2, 6))
            }.glassCard().textSelection(.enabled)
        }
    }
}
