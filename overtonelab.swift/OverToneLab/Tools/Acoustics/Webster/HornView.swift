import SwiftUI

struct HornView: View {
    @ObservedObject var vm: HornViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Exponential horn")
                NumberField(title: "Throat diameter", value: $vm.throatDiaCm, unit: "cm", range: 0.1...200)
                NumberField(title: "Mouth diameter", value: $vm.mouthDiaCm, unit: "cm", range: 0.1...1000)
                NumberField(title: "Axial length", value: $vm.lengthCm, unit: "cm", range: 1...1000)
                ResultRow(label: "Cutoff frequency", value: "\(Fmt.f(vm.cutoffHz, 1)) Hz", emphasis: true, id: "result.webster")
                ResultRow(label: "Flare constant m", value: "\(Fmt.f(vm.flareM, 3)) /m")
            }.glassCard()
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(title: "Areas")
                ResultRow(label: "Throat area", value: "\(Fmt.f(vm.throatArea * 1e4, 1)) cm²")
                ResultRow(label: "Mouth area", value: "\(Fmt.f(vm.mouthArea * 1e4, 1)) cm²")
                Text("The horn only loads efficiently above the cutoff. Aim the flare cutoff about an octave below the lowest note you need.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
