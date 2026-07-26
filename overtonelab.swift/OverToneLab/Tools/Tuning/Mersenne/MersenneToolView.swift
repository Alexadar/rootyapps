import SwiftUI

struct MersenneToolView: View {
    @StateObject private var vm = StringsViewModel()
    @State private var screen = initialScreen()
    var body: some View {
        SubScreenPicker(titles: ["Tension", "Frets", "Reference"], selection: $screen)
        switch screen {
        case 0: TensionView(vm: vm)
        case 1: FretsView(vm: vm)
        default: MersenneReferenceView()
        }
    }
}
