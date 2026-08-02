import SwiftUI

struct AirToolView: View {
    @StateObject private var vm = AirAbsorptionViewModel()
    @State private var screen = initialScreen()
    var body: some View {
        SubScreenPicker(titles: ["Absorption", "Reference"], selection: $screen)
        switch screen {
        case 0: AirAbsorptionView(vm: vm)
        default: AirReferenceView()
        }
    }
}
