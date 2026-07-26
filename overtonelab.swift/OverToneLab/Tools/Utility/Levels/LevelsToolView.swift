import SwiftUI

struct LevelsToolView: View {
    @StateObject private var vm = LevelsViewModel()
    @State private var screen = initialScreen()
    var body: some View {
        SubScreenPicker(titles: ["dB Convert", "Compare", "Dynamic Range"], selection: $screen)
        switch screen {
        case 0: DBConvertView(vm: vm)
        case 1: CompareView(vm: vm)
        default: DynamicRangeView(vm: vm)
        }
    }
}
