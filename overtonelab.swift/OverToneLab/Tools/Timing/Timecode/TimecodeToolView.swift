import SwiftUI

struct TimecodeToolView: View {
    @StateObject private var vm = TimecodeViewModel()
    @State private var screen = initialScreen()
    var body: some View {
        SubScreenPicker(titles: ["Frames → TC", "TC → Frames"], selection: $screen)
        switch screen {
        case 0: FramesView(vm: vm)
        default: TCConvertView(vm: vm)
        }
    }
}
