import SwiftUI

struct PitchToolView: View {
    @StateObject private var vm = PitchViewModel()
    @State private var screen = initialScreen()
    var body: some View {
        SubScreenPicker(titles: ["Note↔Freq", "Harmonics", "Beats", "Doppler"], selection: $screen)
        switch screen {
        case 0: NoteFreqView(vm: vm)
        case 1: HarmonicsView(vm: vm)
        case 2: BeatsView(vm: vm)
        default: DopplerView(vm: vm)
        }
    }
}
