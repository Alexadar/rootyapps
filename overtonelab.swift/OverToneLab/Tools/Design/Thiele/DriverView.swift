import SwiftUI

struct DriverView: View {
    @ObservedObject var vm: ThieleViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Thiele-Small parameters")
                NumberField(title: "Resonance Fs", value: $vm.fs, unit: "Hz", range: 1...200)
                NumberField(title: "Total Q  Qts", value: $vm.qts, unit: "", range: 0.05...5)
                NumberField(title: "Compliance Vas", value: $vm.vas, unit: "L", range: 0.1...10000)
            }.glassCard()
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(title: "Guidance")
                Text(L.loc(vm.suggestedAlignment)).font(.callout)
                ResultRow(label: "Sealed Vb for Qtc 0.707", value: "\(Fmt.f(vm.vbForTarget, 1)) L", emphasis: true, id: "result.thiele")
                Text("From the driver's own datasheet parameters. Qtc 0.707 is the maximally-flat (Butterworth) sealed alignment.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
