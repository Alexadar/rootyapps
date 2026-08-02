import SwiftUI

struct InterferenceBoundaryView: View {
    @ObservedObject var vm: InterferenceViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Source & boundary")
                NumberField(title: "Distance to boundary", value: $vm.distance, unit: "m", range: 0.05...10)
                NumberField(title: "Speed of sound", value: $vm.speed, unit: "m/s", range: 330...350)
                NumberField(title: "Reflection gain", value: $vm.reflectionGain, unit: "dB", range: -20...0)
                ResultRow(label: "First notch", value: "\(Fmt.f(vm.firstNotch, 0)) Hz", emphasis: true, id: "result.sbir")
                ResultRow(label: "First reinforcement", value: "\(Fmt.f(vm.firstPeak, 0)) Hz")
                ResultRow(label: "Notch depth",
                          value: vm.nullDepth.isInfinite ? "−∞ dB" : "\(Fmt.signed(vm.nullDepth, 1)) dB")
                ResultRow(label: "Reinforcement", value: "\(Fmt.signed(vm.peakGain, 1)) dB")
            }.glassCard()

            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: "Notch series (Hz)")
                ForEach(Array(vm.notches.enumerated()), id: \.offset) { i, f in
                    HStack {
                        Text("Notch \(i + 1)").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Fmt.f(f, 0)) Hz").monospacedDigit().foregroundStyle(OTL.textPrimary)
                    }.font(.callout)
                }
            }.glassCard()

            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Place it")
                NumberField(title: "Keep notch above", value: $vm.targetHz, unit: "Hz", range: 20...2000)
                ResultRow(label: "Max distance", value: "\(Fmt.f(vm.suggestedDistance, 2)) m")
            }.glassCard()
        }
    }
}
