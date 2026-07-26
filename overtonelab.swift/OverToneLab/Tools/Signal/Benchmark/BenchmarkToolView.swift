import SwiftUI

struct BenchmarkToolView: View {
    @StateObject private var vm = LoudnessViewModel()
    @State private var screen = initialScreen()
    var body: some View {
        SubScreenPicker(titles: ["Tone", "Target", "Reference"], selection: $screen)
        switch screen {
        case 0: ToneView(vm: vm)
        case 1: TargetView(vm: vm)
        default: BenchmarkReferenceView()
        }
    }
}
