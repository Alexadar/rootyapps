import SwiftUI

struct DelayToolView: View {
    @StateObject private var vm = DelayViewModel()
    @State private var screen = initialScreen()
    var body: some View {
        SubScreenPicker(titles: ["Tempo", "Distance", "Comb"], selection: $screen)
        switch screen {
        case 0: TempoDelayView(vm: vm)
        case 1: DistanceDelayView(vm: vm)
        default: CombView(vm: vm)
        }
    }
}
