import SwiftUI

struct PartchToolView: View {
    @StateObject private var vm = PartchTuningViewModel()
    @State private var screen = initialScreen()
    var body: some View {
        SubScreenPicker(titles: ["Interval", "Ratio", "Reference"], selection: $screen)
        switch screen {
        case 0: PartchIntervalView(vm: vm)
        case 1: RatioView(vm: vm)
        default: PartchReferenceView()
        }
    }
}
