#if os(iOS)
import SwiftUI
import EphemerisKit

/// The five sections, defined once.
///
/// Compact and regular width render completely different chrome — a tab bar against a sidebar — and
/// the one thing that must not fork is *what the sections are*. Two lists of five would drift the
/// first time anyone renamed one, which is the same failure that gave `ChartGeometry` its existence.
enum ChartSection: Int, CaseIterable, Identifiable {
    case chart, positions, aspects, cycle, events, natal

    var id: Int { rawValue }

    /// `LocalizedStringKey`, not `String` — a `String` here silently selects the verbatim
    /// `Text`/`Label` overloads and leaves the navigation English in all 17 languages.
    var title: LocalizedStringKey {
        switch self {
        case .chart:     "Chart"
        case .positions: "Positions"
        case .aspects:   "Aspects"
        case .cycle:     "Cycle"
        case .events:    "Events"
        // "Natal", not "Charts": the first section is already "Chart" (the sky now), and in several
        // languages the plural is a near-homograph — German would read Horoskop against Horoskope.
        case .natal:     "Natal"
        }
    }

    var icon: String {
        switch self {
        case .chart:     "circle.hexagongrid"
        case .positions: "list.star"
        case .aspects:   "point.3.connected.trianglepath.dotted"
        case .cycle:     "arrow.triangle.2.circlepath"
        case .events:    "calendar"
        case .natal:     "person.crop.circle"
        }
    }
}

struct IOSContentView: View {
    @StateObject private var vm = ChartViewModel()
    // Tab selection lives in ReelDriver rather than @State so the preview-reel tour can advance
    // it in-process. Driving it from a UI test meant finding the tab bar, which is translated on
    // every locale and not even exposed as a tabBar on iPad — see ReelDriver for the three ways
    // that failed silently. Normal launches are unaffected: it just holds EPHEMERIS_TAB.
    @StateObject private var reel = ReelDriver()
    /// The real store — iCloud when available, on-device otherwise. The library reports which.
    @StateObject private var natal = NatalViewModel.live()

    /// iPhone gets the tab bar; iPad gets a sidebar. This is the whole point of the refresh — the
    /// app previously rendered the phone layout at every width, so a 13" iPad was a stretched phone.
    @Environment(\.horizontalSizeClass) private var hSize

    /// **The single selection source, deliberately shared by both layouts.**
    ///
    /// `EPHEMERIS_TAB` seeds `reel.tab`, and the sidebar binds to the same value rather than keeping
    /// its own. A sidebar with private state is exactly the documented trap: the deep link would
    /// keep working on iPhone and silently land on the default screen at regular width, which is how
    /// a screenshot pipeline produces a picture of the wrong tab and captions it confidently.
    private var selection: Binding<ChartSection?> {
        Binding(
            get: { ChartSection(rawValue: reel.tab) ?? .chart },
            set: { if let new = $0 { reel.tab = new.rawValue } }
        )
    }

    var body: some View {
        Group {
            if hSize == .regular {
                splitLayout
            } else {
                tabLayout
            }
        }
        // Selecting Chart restarts the demo from the top (onAppear alone is unreliable in
        // TabView, which keeps tab content mounted).
        .onChange(of: reel.tab) { _, newValue in
            if newValue == 0 { vm.startChartDemo() }
        }
        .onAppear { reel.start() }
    }

    // MARK: - Compact — unchanged from the shipping build

    // Native TabView → the real iOS 26 Liquid Glass tab bar (floats in the glass layer).
    // The sky is each tab's `.background(AppBackground())`: gradient + glows are static,
    // only the stars parallax (in-canvas, so no exposed edge), tilt zeroed at launch so
    // holding the phone upright doesn't shove the sky into a black bar.
    private var tabLayout: some View {
        TabView(selection: $reel.tab) {
            ForEach(ChartSection.allCases) { section in
                NavigationStack { page(section) }
                    .tabItem { Label(section.title, systemImage: section.icon) }
                    .tag(section.rawValue)
            }
        }
    }

    // MARK: - Regular — sidebar (Nebula v2)

    private var splitLayout: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            NavigationStack {
                page(ChartSection(rawValue: reel.tab) ?? .chart)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var sidebar: some View {
        List(ChartSection.allCases, selection: selection) { section in
            Label(section.title, systemImage: section.icon)
                .tag(section)
                .accessibilityIdentifier("nav.section.\(section.rawValue)")
        }
        .navigationTitle("Ephemeris Sky")
        .toolbar(removing: .sidebarToggle)
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .safeAreaInset(edge: .top, spacing: 0) { wordmark }
    }

    /// The gradient wordmark from Nebula v2 — pink to cyan, the same two accents the chart wheel
    /// already uses for its aspect chords, so the sidebar reads as part of the same system.
    private var wordmark: some View {
        Text(verbatim: "Ephemeris Sky")
            .font(.system(size: 15, weight: .bold))
            .kerning(0.3)
            .foregroundStyle(
                LinearGradient(colors: [Color(rgbHex: 0xFF4D9D), Color(rgbHex: 0x35E7FF)],
                               startPoint: .leading, endPoint: .trailing)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
    }

    // MARK: - Shared content

    /// One page builder for both chromes, so a section can never render differently depending on
    /// which navigation happens to be on screen.
    @ViewBuilder
    private func page(_ section: ChartSection) -> some View {
        if section == .natal {
            // A List with its own navigation, not a stack of cards — so it gets the chrome but not
            // the ScrollView the card sections need.
            ChartLibraryView(vm: natal)
                .navigationDestination(item: $natal.openChart) { chart in
                    NatalChartView(vm: natal, chart: chart)
                }
                .settingsToolbar()
        } else {
            ScrollView {
                VStack(spacing: 16) { content(section) }
                    .padding()
            }
            .background(AppBackground())
            .navigationTitle(section.title)
            .settingsToolbar()
        }
    }

    @ViewBuilder
    private func content(_ section: ChartSection) -> some View {
        switch section {
        case .chart:
            MomentControls(vm: vm)
            ChartWheel(positions: vm.positions, aspects: vm.aspects, houses: vm.houses)
                .onAppear { vm.startChartDemo() }
                .onDisappear { vm.stopChartDemo() }
            TightestAspects(aspects: vm.aspects)
            HousesCard(vm: vm)
        case .positions:
            MomentControls(vm: vm)
            PositionsTable(positions: vm.positions)
        case .aspects:
            AspectsList(aspects: vm.aspects)
        case .cycle:
            CycleView(vm: vm)
        case .events:
            EventsView(events: vm.timelineEvents, now: vm.instant)
        case .natal:
            // Empty — the library owns its own scrolling and navigation, so it is not wrapped in
            // `page(_:)` like the card sections. Handled in `page(_:)` below.
            EmptyView()
        }
    }
}
#endif
