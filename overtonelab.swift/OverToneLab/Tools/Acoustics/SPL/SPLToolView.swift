import SwiftUI

struct SPLToolView: View {
    @StateObject private var vm = SPLViewModel()
    @State private var screen = initialScreen()
    var body: some View {
        SubScreenPicker(titles: ["Distance", "Summation", "Reference"], selection: $screen)
        switch screen {
        case 0: SPLDistanceView(vm: vm)
        case 1: SummationView(vm: vm)
        default: SPLReferenceView()
        }
    }
}
