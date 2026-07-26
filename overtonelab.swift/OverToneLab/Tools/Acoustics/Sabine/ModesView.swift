import SwiftUI

struct ModesView: View {
    @ObservedObject var vm: RoomViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Room dimensions")
                NumberField(title: "Length", value: $vm.length, unit: "m", range: 0.1...100)
                NumberField(title: "Width", value: $vm.width, unit: "m", range: 0.1...100)
                NumberField(title: "Height", value: $vm.height, unit: "m", range: 0.1...100)
            }.glassCard()
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: "Axial modes (Hz)")
                ForEach(vm.axialModes, id: \.name) { m in
                    HStack {
                        Text(m.name).foregroundStyle(.secondary).frame(width: 74, alignment: .leading)
                        Spacer()
                        Text(m.freqs.map { Fmt.f($0, 1) }.joined(separator: "  ·  ")).monospacedDigit()
                    }.font(.callout)
                }
            }.glassCard()
        }
    }
}
