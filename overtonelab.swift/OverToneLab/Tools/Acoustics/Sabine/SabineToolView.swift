import SwiftUI

struct SabineToolView: View {
    @StateObject private var vm = RoomViewModel()
    @State private var screen = initialScreen()
    var body: some View {
        SubScreenPicker(titles: ["Reverb", "Modes", "Reference"], selection: $screen)
        switch screen {
        case 0: ReverbView(vm: vm)
        case 1: ModesView(vm: vm)
        default: SabineReferenceView()
        }
    }
}
