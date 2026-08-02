import SwiftUI

struct AirAbsorptionView: View {
    @ObservedObject var vm: AirAbsorptionViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Conditions")
                NumberField(title: "Temperature", value: $vm.temp, unit: "°C", range: -20...50)
                NumberField(title: "Humidity", value: $vm.humidity, unit: "%", range: 0...100)
                NumberField(title: "Pressure", value: $vm.pressure, unit: "kPa", range: 80...110)
                ResultRow(label: "Speed of sound", value: "\(Fmt.f(vm.speed, 1)) m/s", emphasis: true, id: "result.air")
            }.glassCard()

            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "At frequency")
                NumberField(title: "Frequency", value: $vm.freq, unit: "Hz", range: 20...20000)
                NumberField(title: "Distance", value: $vm.distance, unit: "m", range: 0...1000)
                ResultRow(label: "Absorption", value: "\(Fmt.f(vm.alphaPerKm, 2)) dB/km")
                ResultRow(label: "Loss over distance", value: "\(Fmt.f(vm.loss, 2)) dB")
            }.glassCard()

            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: "Per octave band", trailing: "over \(Fmt.f(vm.distance, 0)) m")
                ForEach(vm.bands, id: \.hz) { b in
                    HStack {
                        Text(bandLabel(b.hz)).monospacedDigit()
                            .frame(width: 66, alignment: .leading).foregroundStyle(OTL.textPrimary)
                        Text("\(Fmt.f(b.perKm, 2)) dB/km").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Fmt.f(b.loss, 2)) dB").monospacedDigit().foregroundStyle(OTL.textTertiary)
                    }.font(.callout)
                }
            }.glassCard()
        }
    }
    private func bandLabel(_ hz: Double) -> String { hz >= 1000 ? "\(Fmt.f(hz / 1000, hz.truncatingRemainder(dividingBy: 1000) == 0 ? 0 : 1)) kHz" : "\(Fmt.f(hz, 0)) Hz" }
}
