import SwiftUI

struct FileToolView: View {
    @StateObject private var vm = FileViewModel()
    @State private var screen = initialScreen()
    var body: some View {
        SubScreenPicker(titles: ["File Size", "Sample Rate"], selection: $screen)
        switch screen {
        case 0: FileSizeView(vm: vm)
        default: SampleRateView(vm: vm)
        }
    }
}
