import SwiftUI

struct PipeView: View {
    @ObservedObject var vm: PipeViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Air column")
                Picker("Ends", selection: $vm.isOpen) { Text("Open–open").tag(true); Text("Closed–open").tag(false) }
                    .pickerStyle(.segmented)
                NumberField(title: "Length", value: $vm.lengthM, unit: "m", range: 0.01...100)
                ResultRow(label: "Fundamental", value: "\(Fmt.f(vm.fundamental, 1)) Hz", emphasis: true)
            }.glassCard()
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(title: "Resonances (Hz)")
                ForEach(vm.harmonics, id: \.index) { h in
                    HStack {
                        Text("#\(h.index)").foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                        Spacer()
                        Text(Fmt.f(h.hz, 1)).monospacedDigit()
                    }.font(.callout)
                }
                Text(vm.isOpen ? "Open pipes sound all harmonics." : "Closed pipes sound only odd harmonics.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
