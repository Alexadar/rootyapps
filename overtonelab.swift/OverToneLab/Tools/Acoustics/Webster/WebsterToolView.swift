import SwiftUI

struct WebsterToolView: View {
    @StateObject private var vm = HornViewModel()
    @State private var screen = initialScreen()
    var body: some View {
        SubScreenPicker(titles: ["Horn", "Helmholtz", "Reference"], selection: $screen)
        switch screen {
        case 0: HornView(vm: vm)
        case 1: HelmholtzView(vm: vm)
        default: WebsterReferenceView()
        }
    }
}
