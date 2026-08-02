import SwiftUI

struct CommaToolView: View {
    @StateObject private var vm = CommaTuningViewModel()
    @State private var screen = initialScreen()
    var body: some View {
        SubScreenPicker(titles: ["EDO", "Interval", "Temperament"], selection: $screen)
        switch screen {
        case 0: EDOView(vm: vm)
        case 1: CommaIntervalView(vm: vm)
        default: TemperamentView(vm: vm)
        }
    }
}
