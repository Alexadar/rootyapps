import SwiftUI

struct TempoView: View {
    @ObservedObject var vm: TempoViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Tempo & bar")
                NumberField(title: "Tempo", value: $vm.bpm, unit: "BPM", range: 1...999)
                Stepper("Beats  \(vm.beats)", value: $vm.beats, in: 1...16)
                Picker("Beat unit", selection: $vm.beatUnit) {
                    Text("/2").tag(2.0); Text("/4").tag(4.0); Text("/8").tag(8.0); Text("/16").tag(16.0)
                }.pickerStyle(.segmented)
                ResultRow(label: "One beat", value: "\(Fmt.f(vm.beatMs, 2)) ms", emphasis: true)
                ResultRow(label: "One bar", value: "\(Fmt.f(vm.barMs, 2)) ms", emphasis: true)
                Text("A quarter note is one beat, so a 4/4 bar at 120 BPM is 2000 ms.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
