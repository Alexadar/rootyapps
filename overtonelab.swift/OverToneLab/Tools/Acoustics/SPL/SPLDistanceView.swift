import SwiftUI

struct SPLDistanceView: View {
    @ObservedObject var vm: SPLViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Distance attenuation")
                NumberField(title: "SPL at reference", value: $vm.spl1, unit: "dB", range: 0...200)
                NumberField(title: "Reference distance", value: $vm.r1, unit: "m", range: 0.01...100000)
                NumberField(title: "New distance", value: $vm.r2, unit: "m", range: 0.01...100000)
                ResultRow(label: "SPL at new distance", value: "\(Fmt.f(vm.splAtR2, 1)) dB", emphasis: true)
                Text("Free-field inverse-square law: every doubling of distance drops the level 6 dB.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
