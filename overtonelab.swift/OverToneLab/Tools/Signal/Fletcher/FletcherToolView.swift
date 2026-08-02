import SwiftUI

struct FletcherToolView: View {
    @StateObject private var vm = WeightingViewModel()
    @State private var screen = initialScreen()
    var body: some View {
        SubScreenPicker(titles: ["Weighting", "Reference"], selection: $screen)
        switch screen {
        case 0: WeightingView(vm: vm)
        default: FletcherReferenceView()
        }
    }
}
