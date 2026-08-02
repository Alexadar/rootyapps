import SwiftUI

struct TCConvertView: View {
    @ObservedObject var vm: TimecodeViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Timecode → frames")
                RateControls(vm: vm)
                Stepper("Hours  \(vm.h)", value: $vm.h, in: 0...23)
                Stepper("Minutes  \(vm.m)", value: $vm.m, in: 0...59)
                Stepper("Seconds  \(vm.s)", value: $vm.s, in: 0...59)
                Stepper("Frames  \(vm.f)", value: $vm.f, in: 0...(vm.fps - 1))
                ResultRow(label: "Total frames", value: Fmt.count(Double(vm.frames)), unit: "fr", emphasis: true)
                ResultRow(label: "Real time", value: Fmt.secs(vm.tcSeconds))
                Text("Drop-frame skips 2 frame numbers each minute (except every 10th) to track real 29.97 fps time.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
