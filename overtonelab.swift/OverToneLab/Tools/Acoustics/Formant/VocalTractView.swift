import SwiftUI

struct VocalTractView: View {
    @ObservedObject var vm: FormantViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Vocal-tract resonance")
                NumberField(title: "Tract length", value: $vm.tractCm, unit: "cm", range: 1...50)
                Text("Modeled as a tube closed at the glottis, open at the lips (quarter-wave).")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(title: "Formants")
                ForEach(vm.formants, id: \.n) { f in
                    ResultRow(label: "F\(f.n)", value: "\(Fmt.f(f.hz, 0)) Hz", emphasis: f.n == 1)
                }
                Text("A neutral 17.5 cm tract gives the classic 500 / 1500 / 2500 Hz.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
