#if os(iOS)
import SwiftUI
import EphemerisKit

struct IOSContentView: View {
    @StateObject private var vm = ChartViewModel()
    // Section selection lives in ReelDriver rather than @State so the preview-reel tour can advance
    // it in-process. Driving it from a UI test meant finding the tab bar, which is translated on
    // every locale and not even exposed as a tabBar on iPad — see ReelDriver for the three ways
    // that failed silently. Normal launches are unaffected: it just holds EPHEMERIS_TAB.
    @StateObject private var reel = ReelDriver()
    /// The real store — iCloud when available, on-device otherwise. The library reports which.
    @StateObject private var natal = NatalViewModel.live()

    /// iPhone gets the tab bar; iPad gets a sidebar. Both read the same selection.
    @Environment(\.horizontalSizeClass) private var hSize

    /// EPHEMERIS_LENS pins which reading of the moment is showing, so a screenshot or a test can
    /// open Houses directly. Without it Houses is unreachable from a launch argument, because it is
    /// a lens now rather than a tab of its own.
    @State private var lens: MomentLens =
        LaunchOverride.value("EPHEMERIS_LENS").flatMap(MomentLens.init(rawValue:))
        ?? LegacyTab.destination(for: LaunchOverride.int("EPHEMERIS_TAB") ?? 0).moment ?? .wheel
    @State private var cyclesLens: CyclesLens =
        LaunchOverride.value("EPHEMERIS_LENS").flatMap(CyclesLens.init(rawValue:))
        ?? LegacyTab.destination(for: LaunchOverride.int("EPHEMERIS_TAB") ?? 0).cycles ?? .timeline

    /// **One selection source, shared by both chromes.**
    ///
    /// A sidebar with private state is the documented trap: the deep link keeps working on iPhone
    /// and silently lands on the default screen at regular width, so the capture pipeline produces
    /// a picture of the wrong screen and captions it confidently.
    private var selection: Binding<ChartSection?> {
        Binding(
            get: { LegacyTab.destination(for: reel.tab).section },
            set: { if let new = $0 { reel.tab = firstLegacyIndex(of: new) } }
        )
    }

    /// Maps a category back to a legacy index so `reel.tab` stays the single source of truth and the
    /// reel tour keeps working unchanged.
    private func firstLegacyIndex(of section: ChartSection) -> Int {
        switch section {
        case .sky:    0
        case .cycles: 4
        case .charts: 5
        }
    }

    private var section: ChartSection { LegacyTab.destination(for: reel.tab).section }

    /// Opens or closes the reel's subject chart. Named rather than inlined so `onAppear` and
    /// `onChange` cannot drift apart.
    private func applyReelStep() {
        guard reel.isReelRun else { return }
        // Load first if needed. `charts` is filled by the library's `.task`, which runs AFTER
        // `onAppear` — so looking for the subject here found an empty array and opened nothing,
        // producing a clean 30-second video that was the library for all five beats.
        if natal.charts.isEmpty { natal.reload() }
        natal.openChart = reel.natalStep >= 1
            ? natal.charts.first { $0.name == "Olena" } ?? natal.charts.first
            : nil
    }

    var body: some View {
        Group {
            if hSize == .regular { splitLayout } else { tabLayout }
        }
        // Selecting Sky restarts the demo from the top (onAppear alone is unreliable in TabView,
        // which keeps content mounted).
        .onChange(of: reel.tab) { _, newValue in
            let d = LegacyTab.destination(for: newValue)
            if let m = d.moment { lens = m }
            if let c = d.cycles { cyclesLens = c }
            if d.section == .sky { vm.startChartDemo() }
        }
        .onAppear {
            // Apply the launch deep link once, so EPHEMERIS_TAB=1 opens Sky on the Table lens
            // rather than Sky's default.
            if LaunchOverride.value("EPHEMERIS_LENS") == nil {
                let d = LegacyTab.destination(for: reel.tab)
                if let m = d.moment { lens = m }
                if let c = d.cycles { cyclesLens = c }
            }
            reel.start()
        }
    }

    // MARK: - Chromes

    // Native TabView → the real iOS 26 Liquid Glass tab bar (floats in the glass layer).
    private var tabLayout: some View {
        TabView(selection: Binding(
            get: { section },
            set: { reel.tab = firstLegacyIndex(of: $0) })) {
            ForEach(ChartSection.allCases) { s in
                NavigationStack { page(s) }
                    .tabItem { Label(s.title, systemImage: s.icon) }
                    .tag(s)
            }
        }
    }

    private var splitLayout: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            NavigationStack { page(section) }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var sidebar: some View {
        List(ChartSection.allCases, selection: selection) { s in
            Label(s.title, systemImage: s.icon)
                .tag(s)
                .accessibilityIdentifier("nav.section.\(s.rawValue)")
        }
        .navigationTitle("Ephemeris Sky")
        .toolbar(removing: .sidebarToggle)
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .safeAreaInset(edge: .top, spacing: 0) { wordmark }
    }

    /// The gradient wordmark from Nebula v2 — pink to cyan, the same accents the wheel uses for its
    /// aspect chords, so the sidebar reads as part of the same system.
    private var wordmark: some View {
        Text(verbatim: "Ephemeris Sky")
            .font(.system(size: 15, weight: .bold))
            .kerning(0.3)
            .foregroundStyle(
                LinearGradient(colors: [Color(rgbHex: 0xFF4D9D), Color(rgbHex: 0x35E7FF)],
                               startPoint: .leading, endPoint: .trailing))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
    }

    // MARK: - Pages

    @ViewBuilder
    private func page(_ s: ChartSection) -> some View {
        switch s {
        case .charts:
            ChartLibraryView(vm: natal)
                .navigationDestination(item: $natal.openChart) { chart in
                    NatalChartView(vm: natal, chart: chart,
                                   reelLens: reel.isReelRun ? reel.natalLens : nil,
                                   reelTransits: reel.isReelRun ? reel.natalTransits : nil,
                                   reelScrollNudge: reel.isReelRun ? reel.natalScrollNudge : nil,
                                   reelFacet: reel.isReelRun ? reel.natalFacet : nil,
                                   reelPartner: reel.isReelRun ? reel.natalPartner : nil)
                }
                .settingsToolbar()
                // The natal reel opens a chart from in-process rather than by tapping a row — a
                // row lookup is exactly the kind of miss that produced a finished, silently wrong
                // video before. No effect outside a reel run.
                //
                // Applied on APPEAR as well as on change, and that is not belt-and-braces. The tour
                // sets tab=5 and natalStep=1 in the same turn, so by the time this page mounts the
                // value has already changed and `onChange` alone never fires — which produced a
                // clean 30-second video that was the library for every one of its five beats.
                .onAppear { applyReelStep() }
                .onChange(of: reel.natalStep) { _, _ in applyReelStep() }
                // And once more when the library actually has charts, in case the load
                // lands after both of the above.
                .onChange(of: natal.charts.count) { _, _ in applyReelStep() }
        case .sky, .cycles:
            ScrollView {
                VStack(spacing: 16) { content(s) }
                    .padding()
            }
            .background(AppBackground())
            .navigationTitle(s.title)
            .settingsToolbar()
        }
    }

    @ViewBuilder
    private func content(_ s: ChartSection) -> some View {
        switch s {
        case .sky:
            // The Moment control lives ONLY here — it is the thing every lens below is reading.
            MomentControls(vm: vm)
            MomentReadout(moment: vm.skyMoment, lens: $lens, houseSystem: $vm.houseSystem)
                .onAppear { vm.startChartDemo() }
                .onDisappear { vm.stopChartDemo() }
        case .cycles:
            Picker("Cycles", selection: $cyclesLens) {
                ForEach(CyclesLens.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("input.cyclesLens")

            switch cyclesLens {
            case .timeline:
                EventsView(events: vm.timelineEvents, now: vm.instant)
            case .synodic:
                CycleView(phase: vm.cyclePhase, upcoming: vm.upcomingEvents,
                          selectedBody: $vm.cycleBody)
            }
        case .charts:
            EmptyView()
        }
    }
}
#endif
