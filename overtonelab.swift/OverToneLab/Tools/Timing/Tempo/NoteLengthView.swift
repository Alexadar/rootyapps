import SwiftUI

struct NoteLengthView: View {
    @ObservedObject var vm: TempoViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Note length")
                NumberField(title: "Tempo", value: $vm.bpm, unit: "BPM", range: 1...999)
                Picker("Note", selection: $vm.division) {
                    Text("1/1").tag(1.0); Text("1/2").tag(2.0); Text("1/4").tag(4.0)
                    Text("1/8").tag(8.0); Text("1/16").tag(16.0); Text("1/32").tag(32.0)
                }.pickerStyle(.segmented)
                Toggle("Dotted", isOn: $vm.dotted)
                Toggle("Triplet", isOn: $vm.triplet)
                ResultRow(label: "Duration", value: "\(Fmt.f(vm.noteMs, 2)) ms", emphasis: true)
                ResultRow(label: "Rate", value: "\(Fmt.f(vm.noteHz, 3)) Hz")
            }.glassCard()
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(title: "Common subdivisions")
                ForEach(vm.subdivisionTable, id: \.name) { row in
                    HStack { Text(row.name).foregroundStyle(.secondary); Spacer(); Text("\(Fmt.f(row.ms, 1)) ms").monospacedDigit() }
                        .font(.callout)
                }
            }.glassCard()
        }
    }
}
