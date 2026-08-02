import SwiftUI

struct InterferenceToolView: View {
    @StateObject private var vm = InterferenceViewModel()
    @State private var screen = initialScreen()
    var body: some View {
        SubScreenPicker(titles: ["Boundary", "Two-source", "Reference"], selection: $screen)
        switch screen {
        case 0: InterferenceBoundaryView(vm: vm)
        case 1: InterferenceTwoSourceView(vm: vm)
        default: InterferenceReferenceView()
        }
    }
}
