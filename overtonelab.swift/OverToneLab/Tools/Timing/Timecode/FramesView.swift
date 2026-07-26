import SwiftUI

struct FramesView: View {
    @ObservedObject var vm: TimecodeViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Frames → timecode")
                RateControls(vm: vm)
                NumberField(title: "Frame count", value: $vm.frameCount, unit: "fr", range: 0...100_000_000)
                ResultRow(label: "Timecode", value: vm.timecodeLabel, emphasis: true)
                ResultRow(label: "Duration", value: Fmt.secs(vm.frameSeconds))
            }.glassCard()
        }
    }
}

struct RateControls: View {
    @ObservedObject var vm: TimecodeViewModel
    var body: some View {
        Picker("fps", selection: $vm.fps) {
            Text("24").tag(24); Text("25").tag(25); Text("30").tag(30)
        }.pickerStyle(.segmented)
        if vm.fps == 30 {
            Toggle("Drop-frame (29.97)", isOn: $vm.dropFrame)
        }
    }
}
