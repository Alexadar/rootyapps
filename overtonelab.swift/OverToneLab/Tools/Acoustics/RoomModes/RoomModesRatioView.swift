import SwiftUI

struct RoomModesRatioView: View {
    @ObservedObject var vm: RoomModesViewModel
    var body: some View {
        VStack(spacing: 16) {
            RoomDimsCard(vm: vm)
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Proportion")
                let n = vm.normalized
                ResultRow(label: "Ratio (short:mid:long)",
                          value: "1 : \(Fmt.f(n.1, 2)) : \(Fmt.f(n.2, 2))", emphasis: true)
                ResultRow(label: "Nearest published",
                          value: "\(vm.nearest.name)")
                ResultRow(label: "  target",
                          value: "1 : \(Fmt.f(vm.nearest.mid, 2)) : \(Fmt.f(vm.nearest.long, 2))")
                ResultRow(label: "Bonello distribution", value: vm.bonello ? "Pass" : "Fail")
                if vm.degenerate {
                    ResultRow(label: "⚠︎ Degenerate", value: "modes pile up")
                }
            }.glassCard()
        }
    }
}
