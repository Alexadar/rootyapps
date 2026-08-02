import SwiftUI

struct RoomModesToolView: View {
    @StateObject private var vm = RoomModesViewModel()
    @State private var screen = initialScreen()
    var body: some View {
        SubScreenPicker(titles: ["Modes", "Ratio", "Reference"], selection: $screen)
        switch screen {
        case 0: RoomModesModesView(vm: vm)
        case 1: RoomModesRatioView(vm: vm)
        default: RoomModesReferenceView()
        }
    }
}

/// Shared room-dimension input card (edits reflect on both Modes and Ratio screens).
struct RoomDimsCard: View {
    @ObservedObject var vm: RoomModesViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Room dimensions")
            NumberField(title: "Length", value: $vm.length, unit: "m", range: 1...30)
            NumberField(title: "Width", value: $vm.width, unit: "m", range: 1...30)
            NumberField(title: "Height", value: $vm.height, unit: "m", range: 1...20)
            NumberField(title: "Speed of sound", value: $vm.speed, unit: "m/s", range: 330...350)
        }.glassCard()
    }
}
