import SwiftUI

struct SRAToolView: View {
    @StateObject private var vm = SRAViewModel()
    @State private var screen = initialScreen()
    var body: some View {
        SubScreenPicker(titles: ["Array", "Presets", "Reference"], selection: $screen)
        switch screen {
        case 0: SRAArrayView(vm: vm)
        case 1: SRAPresetsView(vm: vm)
        default: SRAReferenceView()
        }
    }
}
