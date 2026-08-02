import SwiftUI

struct PanToolView: View {
    @StateObject private var vm = PanViewModel()
    var body: some View {
        PanLawView(vm: vm)
    }
}
