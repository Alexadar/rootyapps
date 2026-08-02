import SwiftUI

struct ButterworthToolView: View {
    @StateObject private var vm = FilterViewModel()
    @State private var screen = initialScreen()
    var body: some View {
        SubScreenPicker(titles: ["Filter", "Crossover", "Reference"], selection: $screen)
        switch screen {
        case 0: FilterView(vm: vm)
        case 1: CrossoverView(vm: vm)
        default: ButterworthReferenceView()
        }
    }
}
