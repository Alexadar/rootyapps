import SwiftUI

struct FileSizeView: View {
    @ObservedObject var vm: FileViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Uncompressed audio size")
                Picker("Sample rate", selection: $vm.sampleRate) {
                    Text("44.1k").tag(44100.0); Text("48k").tag(48000.0)
                    Text("96k").tag(96000.0); Text("192k").tag(192000.0)
                }.pickerStyle(.segmented)
                Picker("Bit depth", selection: $vm.bitDepth) {
                    Text("16").tag(16.0); Text("24").tag(24.0); Text("32").tag(32.0)
                }.pickerStyle(.segmented)
                Stepper("Channels  \(Int(vm.channels))", value: $vm.channels, in: 1...8)
                NumberField(title: "Duration", value: $vm.minutes, unit: "min", range: 0...100000)
                ResultRow(label: "Size", value: "\(Fmt.f(vm.megabytes, 1)) MB", emphasis: true, id: "result.file")
                ResultRow(label: "Bytes", value: Fmt.count(vm.bytes), unit: "B")
                Text("PCM data only (WAV/AIFF header excluded).")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
