import SwiftUI

struct TempoToolView: View {
    @StateObject private var vm = TempoViewModel()
    @State private var screen = initialScreen()
    var body: some View {
        SubScreenPicker(titles: ["Note", "Tempo", "Samples", "Varispeed"], selection: $screen)
        switch screen {
        case 0: NoteLengthView(vm: vm)
        case 1: TempoView(vm: vm)
        case 2: SamplesView(vm: vm)
        default: VarispeedView(vm: vm)
        }
    }
}
