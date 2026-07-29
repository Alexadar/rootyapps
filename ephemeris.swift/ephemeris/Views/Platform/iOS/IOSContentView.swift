#if os(iOS)
import SwiftUI
import EphemerisKit

struct IOSContentView: View {
    @StateObject private var vm = ChartViewModel()
    // Tab selection lives in ReelDriver rather than @State so the preview-reel tour can advance
    // it in-process. Driving it from a UI test meant finding the tab bar, which is translated on
    // every locale and not even exposed as a tabBar on iPad — see ReelDriver for the three ways
    // that failed silently. Normal launches are unaffected: it just holds EPHEMERIS_TAB.
    @StateObject private var reel = ReelDriver()

    // Native TabView → the real iOS 26 Liquid Glass tab bar (floats in the glass layer).
    // The sky is each tab's `.background(AppBackground())`: gradient + glows are static,
    // only the stars parallax (in-canvas, so no exposed edge), tilt zeroed at launch so
    // holding the phone upright doesn't shove the sky into a black bar.
    var body: some View {
        TabView(selection: $reel.tab) {
            tab("Chart", "circle.hexagongrid", 0) {
                MomentControls(vm: vm)
                ChartWheel(positions: vm.positions, aspects: vm.aspects, houses: vm.houses)
                    .onAppear { vm.startChartDemo() }
                    .onDisappear { vm.stopChartDemo() }
                HousesCard(vm: vm)
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
        // Selecting Chart restarts the demo from the top (onAppear alone is unreliable in
        // TabView, which keeps tab content mounted).
        .onChange(of: reel.tab) { _, newValue in
            if newValue == 0 { vm.startChartDemo() }
        }
        .onAppear { reel.start() }
    }

    // `title` is a LocalizedStringKey so `navigationTitle`/`Label` hit their localizing overloads;
    // a `String` here would silently select the verbatim ones and leave the tab bar English.
    private func tab<Content: View>(_ title: LocalizedStringKey, _ icon: String, _ tag: Int,
                                    @ViewBuilder _ content: () -> Content) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) { content() }
                    .padding()
            }
            .background(AppBackground())
            .navigationTitle(title)
            .settingsToolbar()
        }
        .tabItem { Label(title, systemImage: icon) }
        .tag(tag)
    }
}
#endif
