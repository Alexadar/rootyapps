#if os(iOS)
import SwiftUI
import EphemerisKit

struct IOSContentView: View {
    @StateObject private var vm = ChartViewModel()
    // Lets screenshot tooling open a specific tab via SIMCTL_CHILD_EPHEMERIS_TAB.
    @State private var selection = Int(ProcessInfo.processInfo.environment["EPHEMERIS_TAB"] ?? "0") ?? 0

    // Native TabView → the real iOS 26 Liquid Glass tab bar (floats in the glass layer).
    // The sky is each tab's `.background(AppBackground())`: gradient + glows are static,
    // only the stars parallax (in-canvas, so no exposed edge), tilt zeroed at launch so
    // holding the phone upright doesn't shove the sky into a black bar.
    var body: some View {
        TabView(selection: $selection) {
            tab("Chart", "circle.hexagongrid", 0) {
                MomentControls(vm: vm)
                ChartWheel(positions: vm.positions, aspects: vm.aspects)
                    .onAppear { vm.startChartDemo() }
                    .onDisappear { vm.stopChartDemo() }
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
        // Selecting Chart restarts the demo from the top — the reel tour bounces away and back
        // so the choreography replays inside the recorded window (onAppear alone is unreliable
        // in TabView, which keeps tab content mounted).
        .onChange(of: selection) { _, newValue in
            if newValue == 0 { vm.startChartDemo() }
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
