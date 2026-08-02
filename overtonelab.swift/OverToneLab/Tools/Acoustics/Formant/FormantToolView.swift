import SwiftUI

struct FormantToolView: View {
    @StateObject private var vm = FormantViewModel()
    @State private var screen = initialScreen()
    var body: some View {
        SubScreenPicker(titles: ["Vocal Tract", "Vowels", "Reference"], selection: $screen)
        switch screen {
        case 0: VocalTractView(vm: vm)
        case 1: VowelsView(vm: vm)
        default: FormantReferenceView()
        }
    }
}
