import SwiftUI

struct SampleRateView: View {
    @ObservedObject var vm: FileViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Sample rate & Nyquist")
                Picker("Sample rate", selection: $vm.sampleRate) {
                    Text("44.1k").tag(44100.0); Text("48k").tag(48000.0)
                    Text("96k").tag(96000.0); Text("192k").tag(192000.0)
                }.pickerStyle(.segmented)
                ResultRow(label: "Nyquist frequency", value: "\(Fmt.f(vm.nyquist, 0)) Hz", emphasis: true)
                Text("The highest frequency a sample rate can represent is half of it. Anything above must be filtered out to avoid aliasing.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
