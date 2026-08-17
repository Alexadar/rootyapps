import SwiftUI

struct TempoDelayView: View {
    @EnvironmentObject private var handoff: MeasurementHandoff
    @EnvironmentObject private var provenance: FieldProvenance
    @ObservedObject var vm: DelayViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Tempo-synced delay")
                NumberField(title: "Tempo", value: $vm.bpm, unit: "BPM", range: 1...999,
                            field: FieldKey(tool: "delay", field: "bpm"))
                Picker("Note", selection: $vm.division) {
                    Text("1/4").tag(4.0); Text("1/8").tag(8.0); Text("1/16").tag(16.0); Text("1/32").tag(32.0)
                }.pickerStyle(.segmented)
                Toggle("Dotted", isOn: $vm.dotted)
                Toggle("Triplet", isOn: $vm.triplet)
                ResultRow(label: "Delay time", value: "\(Fmt.f(vm.delayMs, 2)) ms", emphasis: true, id: "result.delay")
                ResultRow(label: "Modulation rate", value: "\(Fmt.f(vm.delayHz, 3)) Hz")
            }.glassCard()
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(title: "Straight · dotted · triplet (ms)")
                ForEach(vm.table, id: \.name) { r in
                    HStack {
                        Text(r.name).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
                        Spacer()
                        Text(Fmt.f(r.straight, 0)); Text("·").foregroundStyle(.tertiary)
                        Text(Fmt.f(r.dotted, 0)); Text("·").foregroundStyle(.tertiary)
                        Text(Fmt.f(r.triplet, 0))
                    }.font(.callout).monospacedDigit()
                }
            }.glassCard()
        }
        .onAppear {
            // A value sent from Analysis lands here, marked measured, remembering what it displaced.
            handoff.apply(FieldKey(tool: "delay", field: "bpm"), into: $vm.bpm, provenance: provenance)
        }
    }
}
