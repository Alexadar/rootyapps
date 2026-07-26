import SwiftUI

struct SamplesView: View {
    @ObservedObject var vm: TempoViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Time ↔ samples")
                NumberField(title: "Time", value: $vm.timeMs, unit: "ms", range: 0...3_600_000)
                Picker("Sample rate", selection: $vm.sampleRate) {
                    Text("44.1k").tag(44100.0); Text("48k").tag(48000.0)
                    Text("96k").tag(96000.0); Text("192k").tag(192000.0)
                }.pickerStyle(.segmented)
                ResultRow(label: "Samples", value: Fmt.f(vm.samples, 0), unit: "samples", emphasis: true)
                Text("Sample-accurate edit points: samples = seconds × sample rate.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
