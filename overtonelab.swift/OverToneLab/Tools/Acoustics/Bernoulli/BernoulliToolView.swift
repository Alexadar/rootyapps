import SwiftUI

struct BernoulliToolView: View {
    @StateObject private var vm = PipeViewModel()
    @State private var screen = initialScreen()
    var body: some View {
        SubScreenPicker(titles: ["Pipe", "End", "Reference"], selection: $screen)
        switch screen {
        case 0: PipeView(vm: vm)
        case 1: EndView(vm: vm)
        default: BernoulliReferenceView()
        }
    }
}
