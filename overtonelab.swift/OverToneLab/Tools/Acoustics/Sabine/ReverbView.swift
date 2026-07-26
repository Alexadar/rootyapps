import SwiftUI

struct ReverbView: View {
    @ObservedObject var vm: RoomViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Room")
                NumberField(title: "Volume", value: $vm.volume, unit: "m³", range: 0.1...1000000)
                NumberField(title: "Absorption ΣSα", value: $vm.absorption, unit: "sabins", range: 0.01...1000000)
                ResultRow(label: "RT60 (Sabine)", value: "\(Fmt.f(vm.sabineRT60, 2)) s", emphasis: true)
                ResultRow(label: "Schroeder freq", value: "\(Fmt.f(vm.schroeder, 0)) Hz")
            }.glassCard()
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Eyring (high absorption)")
                NumberField(title: "Surface area", value: $vm.surface, unit: "m²", range: 0.1...1000000)
                NumberField(title: "Avg. absorption ā", value: $vm.avgAbsorption, range: 0.001...1)
                ResultRow(label: "RT60 (Eyring)", value: "\(Fmt.f(vm.eyringRT60, 2)) s", emphasis: true)
            }.glassCard()
        }
    }
}
