import SwiftUI

struct TargetView: View {
    @ObservedObject var vm: LoudnessViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Match a target")
                NumberField(title: "Your measured loudness", value: $vm.measuredInput, unit: "LUFS", range: -60...0)
                Picker("Target", selection: $vm.platform) {
                    ForEach(LoudnessViewModel.Platform.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                ResultRow(label: "\(vm.platform.rawValue) target", value: "\(Fmt.f(vm.platform.target, 0)) LUFS")
                ResultRow(label: "Apply gain", value: "\(Fmt.signed(vm.gain, 1)) LU", emphasis: true)
                Text(vm.gain < 0
                     ? "Turn down \(Fmt.f(-vm.gain, 1)) dB — the platform will otherwise attenuate you."
                     : "You could raise up to \(Fmt.f(vm.gain, 1)) dB, watching true-peak headroom.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
