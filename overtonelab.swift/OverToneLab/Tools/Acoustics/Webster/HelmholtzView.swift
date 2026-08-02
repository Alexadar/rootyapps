import SwiftUI

struct HelmholtzView: View {
    @ObservedObject var vm: HornViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Helmholtz resonator")
                NumberField(title: "Neck diameter", value: $vm.neckDiaCm, unit: "cm", range: 0.1...100)
                NumberField(title: "Neck length", value: $vm.neckLenCm, unit: "cm", range: 0...200)
                NumberField(title: "Cavity volume", value: $vm.cavityLiters, unit: "L", range: 0.01...10000)
                ResultRow(label: "Resonant frequency", value: "\(Fmt.f(vm.helmholtzHz, 1)) Hz", emphasis: true)
                ResultRow(label: "Effective neck length", value: "\(Fmt.f(vm.effLenM * 100, 2)) cm")
                Text("Includes a ≈0.85·r end correction on the open neck. Bass-reflex ports, ocarinas and bottle tones all follow this.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
