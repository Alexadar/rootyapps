import SwiftUI

struct ToneView: View {
    @ObservedObject var vm: LoudnessViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Reference tone")
                NumberField(title: "Frequency", value: $vm.toneHz, unit: "Hz", range: 1...24000)
                NumberField(title: "Peak level", value: $vm.toneDbfs, unit: "dBFS", range: -120...0)
            }.glassCard()
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(title: "Integrated loudness")
                ResultRow(label: "Measured (stereo)", value: "\(Fmt.f(vm.measuredLUFS, 2)) LUFS", emphasis: true)
                Text("A steady sine, K-weighted and gated per ITU-R BS.1770. Change the level and the reading tracks it — this is the same engine you'd run on a full mix.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
