import SwiftUI

struct DopplerView: View {
    @ObservedObject var vm: PitchViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Doppler shift")
                NumberField(title: "Source frequency", value: $vm.sourceHz, unit: "Hz", range: 1...20000)
                NumberField(title: "Source speed (+toward)", value: $vm.vSource, unit: "m/s", range: -340...340)
                NumberField(title: "Observer speed (+toward)", value: $vm.vObserver, unit: "m/s", range: -340...340)
                ResultRow(label: "Observed", value: "\(Fmt.f(vm.observedHz, 1)) Hz", emphasis: true)
                ResultRow(label: "Shift", value: "\(Fmt.signed(vm.shiftCents, 0)) ¢")
                Text("Positive speeds close the gap (pitch up); negative open it (pitch down).")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
