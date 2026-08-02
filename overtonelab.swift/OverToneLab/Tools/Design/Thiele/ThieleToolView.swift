import SwiftUI

struct ThieleToolView: View {
    @StateObject private var vm = ThieleViewModel()
    @State private var screen = initialScreen()
    var body: some View {
        SubScreenPicker(titles: ["Driver", "Sealed", "Ported", "Reference"], selection: $screen)
        switch screen {
        case 0: DriverView(vm: vm)
        case 1: SealedView(vm: vm)
        case 2: PortedView(vm: vm)
        default: ThieleReferenceView()
        }
    }
}
