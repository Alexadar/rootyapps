import SwiftUI

struct PanLawView: View {
    @ObservedObject var vm: PanViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Pan law")
                Picker("Law", selection: $vm.lawIndex) {
                    Text("−3 dB").tag(0); Text("−6 dB").tag(1); Text("−4.5 dB").tag(2)
                }.pickerStyle(.segmented)
                HStack {
                    Text("L").foregroundStyle(.secondary)
                    Slider(value: $vm.position, in: -1...1)
                    Text("R").foregroundStyle(.secondary)
                }
                ResultRow(label: "Left gain", value: "\(Fmt.f(vm.leftDB, 2)) dB", emphasis: true)
                ResultRow(label: "Right gain", value: "\(Fmt.f(vm.rightDB, 2)) dB", emphasis: true)
                ResultRow(label: "Centre drop", value: "\(Fmt.f(vm.centerDrop, 2)) dB")
                Text("Equal-power (−3 dB) keeps loudness constant across the stereo field; linear (−6 dB) keeps summed level constant in mono.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
