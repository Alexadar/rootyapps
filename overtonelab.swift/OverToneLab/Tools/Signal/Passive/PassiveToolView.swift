import SwiftUI

struct PassiveToolView: View {
    @StateObject private var vm = PassiveViewModel()
    @State private var screen = initialScreen()
    var body: some View {
        SubScreenPicker(titles: ["RC / RL", "LC", "Reference"], selection: $screen)
        switch screen {
        case 0: RCView(vm: vm)
        case 1: LCView(vm: vm)
        default: PassiveReferenceView()
        }
    }
}
