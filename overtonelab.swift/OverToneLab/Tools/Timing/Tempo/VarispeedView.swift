import SwiftUI

struct VarispeedView: View {
    @ObservedObject var vm: TempoViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Varispeed")
                NumberField(title: "Pitch shift", value: $vm.semitones, unit: "st", range: -60...60)
                ResultRow(label: "Speed ratio", value: "\(Fmt.f(vm.rateRatio, 4))×", emphasis: true)
                ResultRow(label: "Speed change", value: "\(Fmt.signed(vm.ratePercent, 2)) %")
                Text("Tape/varispeed couples pitch and speed: +12 st doubles the playback rate.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
