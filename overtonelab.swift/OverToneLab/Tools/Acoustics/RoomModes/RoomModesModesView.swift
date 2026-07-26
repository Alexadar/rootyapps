import SwiftUI
import RoomModesKit

struct RoomModesModesView: View {
    @ObservedObject var vm: RoomModesViewModel
    var body: some View {
        VStack(spacing: 16) {
            RoomDimsCard(vm: vm)
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Analysis")
                NumberField(title: "Max frequency", value: $vm.maxFreq, unit: "Hz", range: 50...500)
                ResultRow(label: "Smallest spacing", value: "\(Fmt.f(vm.smallestSpacing, 1)) Hz", emphasis: true)
                ResultRow(label: "Mode count", value: "\(vm.modeCount)")
            }.glassCard()
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: "Modes (Hz)", trailing: "≤ \(Fmt.f(vm.maxFreq, 0)) Hz")
                ForEach(Array(vm.modes.prefix(80).enumerated()), id: \.offset) { _, m in
                    HStack(spacing: 10) {
                        Text("\(Fmt.f(m.hz, 1)) Hz").monospacedDigit()
                            .frame(width: 92, alignment: .leading)
                            .foregroundStyle(OTL.textPrimary)
                        Text(m.type.rawValue).foregroundStyle(.secondary)
                        Spacer()
                        Text("(\(m.nx),\(m.ny),\(m.nz))").monospacedDigit().foregroundStyle(OTL.textTertiary)
                    }.font(.callout)
                }
            }.glassCard()
        }
    }
}
