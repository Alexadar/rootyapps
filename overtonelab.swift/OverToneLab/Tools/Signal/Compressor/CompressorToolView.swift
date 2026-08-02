import SwiftUI

struct CompressorToolView: View {
    @StateObject private var vm = CompressorViewModel()
    @State private var screen = initialScreen()
    var body: some View {
        SubScreenPicker(titles: ["Gain", "Time", "Reference"], selection: $screen)
        switch screen {
        case 0: CompressorGainView(vm: vm)
        case 1: CompressorTimeView(vm: vm)
        default: CompressorReferenceView()
        }
    }
}
