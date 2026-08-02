import SwiftUI

struct BiquadToolView: View {
    @StateObject private var vm = BiquadViewModel()
    @State private var screen = initialScreen()
    var body: some View {
        SubScreenPicker(titles: ["Design", "Reference"], selection: $screen)
        switch screen {
        case 0: BiquadDesignView(vm: vm)
        default: BiquadReferenceView()
        }
    }
}
