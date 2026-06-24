#if os(iOS)
import SwiftUI
import EphemerisKit

struct IOSContentView: View {
    @StateObject private var vm = ChartViewModel()
    // Lets screenshot tooling open a specific tab via SIMCTL_CHILD_EPHEMERIS_TAB.
    @State private var selection = Int(ProcessInfo.processInfo.environment["EPHEMERIS_TAB"] ?? "0") ?? 0

    var body: some View {
        TabView(selection: $selection) {
            tab("Chart", "circle.hexagongrid", 0) {
                MomentControls(vm: vm)
                ChartWheel(positions: vm.positions, aspects: vm.aspects)
            }
            tab("Positions", "list.star", 1) {
                MomentControls(vm: vm)
                PositionsTable(positions: vm.positions)
            }
            tab("Aspects", "point.3.connected.trianglepath.dotted", 2) {
                AspectsList(aspects: vm.aspects)
            }
            tab("Cycle", "arrow.triangle.2.circlepath", 3) {
                CycleView(vm: vm)
            }
            tab("Events", "calendar", 4) {
                EventsView(events: vm.timelineEvents, now: vm.instant)
            }
        }
    }

    private func tab<Content: View>(_ title: String, _ icon: String, _ tag: Int,
                                    @ViewBuilder _ content: () -> Content) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) { content() }
                    .padding()
            }
            .background(AppBackground())
            .navigationTitle(title)
        }
        .tabItem { Label(title, systemImage: icon) }
        .tag(tag)
    }
}
#endif
