#if os(macOS)
import SwiftUI
import EphemerisKit

struct MacOSContentView: View {
    @StateObject private var vm = ChartViewModel()

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ScrollView {
                VStack(spacing: 16) {
                    MomentControls(vm: vm)
                    PositionsTable(positions: vm.positions)
                    AspectsList(aspects: vm.aspects)
                }
                .padding(16)
            }
            .frame(width: 380)

            ScrollView {
                VStack(spacing: 16) {
                    ChartWheel(positions: vm.positions, aspects: vm.aspects)
                    CycleView(vm: vm)
                    EventsView(events: vm.timelineEvents, now: vm.instant)
                }
                .padding(16)
            }
        }
        .frame(minWidth: 900, minHeight: 680)
        .background(AppBackground())
    }
}
#endif
