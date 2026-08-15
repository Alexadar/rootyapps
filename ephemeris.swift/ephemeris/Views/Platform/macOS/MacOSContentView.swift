#if os(macOS)
import SwiftUI
import EphemerisKit

private struct MacTab: Identifiable {
    let id: Int
    /// LocalizedStringKey, not String — `Label`/`help` would otherwise take the verbatim overload.
    let title: LocalizedStringKey
    let icon: String
}

struct MacOSContentView: View {
    /// Read straight from the environment, not via ReelDriver: that type is @MainActor, and
    /// referencing its static from the App's Scene builder stopped the window being created.
    static let isReelRun = LaunchOverride.flag("EPHEMERIS_REEL")

    @StateObject private var vm = ChartViewModel()
    // Lets screenshot tooling open a specific section via EPHEMERIS_TAB. This is a SEPARATE deep-link
    // path from the iOS TabView's, so a tab deep link has to be asserted on the Mac as well —
    // passing on iPhone proves nothing here.
    /// Seeded through the legacy map so EPHEMERIS_TAB=1 still opens Sky on the Table lens — the
    /// screenshot pipeline and three UI tests depend on those indices landing on the same pixels.
    @State private var selection: Int = LegacyTab.destination(
        for: LaunchOverride.int("EPHEMERIS_TAB") ?? 0).section.rawValue

    /// Three categories, matching iOS. Built from `ChartSection` so the two platforms cannot drift
    /// apart about what the sections are.
    private var tabs: [MacTab] {
        ChartSection.allCases.map { .init(id: $0.rawValue, title: $0.title, icon: $0.icon) }
    }

    @State private var lens: MomentLens =
        LaunchOverride.value("EPHEMERIS_LENS").flatMap(MomentLens.init(rawValue:))
        ?? LegacyTab.destination(for: LaunchOverride.int("EPHEMERIS_TAB") ?? 0).moment ?? .wheel
    @State private var cyclesLens: CyclesLens =
        LaunchOverride.value("EPHEMERIS_LENS").flatMap(CyclesLens.init(rawValue:))
        ?? LegacyTab.destination(for: LaunchOverride.int("EPHEMERIS_TAB") ?? 0).cycles ?? .timeline

    @StateObject private var natal = NatalViewModel.live()

    /// Sidebar visibility, bound so the user can collapse it — and so a reel run can record a
    /// **real** state of the app rather than a layout built for the camera.
    ///
    /// This is the difference that matters for the App Store: a collapsed sidebar is something any
    /// user can reach with the toolbar toggle, so a preview recorded that way still depicts the
    /// shipping app. A separate reel-only chrome would not.
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            sidebar
                // Pinned during a reel so the arithmetic below stays exact: 220 sidebar + 1380
                // detail = the 1600 of content that `.windowResizability(.contentSize)` turns into
                // a 1600x900 window. Left flexible otherwise, because a Mac user resizing the
                // sidebar is normal behaviour and nothing downstream depends on it.
                .navigationSplitViewColumnWidth(
                    min: Self.isReelRun ? 220 : 200,
                    ideal: 220,
                    max: Self.isReelRun ? 220 : 300)
        } detail: {
            ScrollView {
                VStack(spacing: 16) { content }
                    // 720 was a phone column centred in an 820-minimum window — the Mac's width was
                    // simply unused. 1180 lets the two-column Chart layout engage while keeping
                    // single-column sections at a readable measure.
                    .frame(maxWidth: 1180)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
            }
            .background(AppBackground())
        }
        .navigationTitle("Ephemeris Sky")
        .settingsToolbar()
        .preferredColorScheme(.dark)   // celestial UI is always dark — keeps glass + text legible
        // A preview-reel run sizes the CONTENT to 16:9, which — because the scene uses
        // `.windowResizability(.contentSize)` — makes the window exactly 1600x900.
        //
        // Done here rather than by resizing the window: the App Store's macOS preview canvas is
        // 1920x1080, and the normal portrait window scaled into it leaves ~480px of black down
        // each side, which is "framing" under Guideline 2.3.4 just as much as a device bezel.
        // Two other routes failed — `.defaultSize` is ignored once macOS has a saved window
        // frame, and touching the Scene builder to branch on the reel flag stopped the app from
        // creating a window at all. Sizing the content leaves both the scene and AppKit alone.
        // min alone is not enough — it is only a floor, and `.contentSize` then lets the content
        // set the height (1010, giving 1600x1010 and still ~100px of bar). Pinning max as well
        // makes it exactly 16:9. Clamping the height is safe: the body is a ScrollView.
        // 848, not 900: `.contentSize` sizes the CONTENT, and the title bar adds 52pt on top —
        // asking for 900 of content produced a 1600x952 window, which is 1.68:1 and still leaves
        // bars in a 16:9 canvas. 1600x848 of content is a 1600x900 window: exactly 16:9.
        .frame(minWidth: Self.isReelRun ? 1600 : 820,
               maxWidth: Self.isReelRun ? 1600 : nil,
               minHeight: Self.isReelRun ? 848 : 640,
               maxHeight: Self.isReelRun ? 848 : nil)
    }

    @ViewBuilder private var content: some View {
        switch ChartSection(rawValue: selection) ?? .sky {
        case .sky:
            // The Moment control lives ONLY here — every lens below reads it.
            MomentControls(vm: vm)
            MomentReadout(moment: vm.skyMoment, lens: $lens, houseSystem: $vm.houseSystem)
                .onAppear { vm.startChartDemo() }
                .onDisappear { vm.stopChartDemo() }
        case .cycles:
            Picker("Cycles", selection: $cyclesLens) {
                ForEach(CyclesLens.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .accessibilityIdentifier("input.cyclesLens")
            switch cyclesLens {
            case .timeline: EventsView(events: vm.timelineEvents, now: vm.instant)
            case .synodic:  CycleView(phase: vm.cyclePhase, upcoming: vm.upcomingEvents,
                                      selectedBody: $vm.cycleBody)
            }
        case .charts:
            // The library brings its own List and navigation; the surrounding ScrollView is
            // harmless because the List sizes itself, and this keeps the section switch uniform.
            NavigationStack {
                ChartLibraryView(vm: natal)
                    .navigationDestination(item: $natal.openChart) { chart in
                        NatalChartView(vm: natal, chart: chart)
                    }
            }
            .frame(minHeight: 520)
        }
    }

    /// Section list — the Mac-native navigation Apple's own apps use, and what Nebula v2 draws.
    ///
    /// Replaces a toolbar capsule of icon-only buttons. Labels rather than icons alone: five
    /// astronomy glyphs in a row are not self-describing, and `help` tooltips only reach a user who
    /// already hovered the right one.
    private var sidebar: some View {
        List(tabs, selection: $selection) { tab in
            Label(tab.title, systemImage: tab.icon)
                .tag(tab.id)
                .accessibilityIdentifier("nav.section.\(tab.id)")
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .safeAreaInset(edge: .top, spacing: 0) {
            Text(verbatim: "Ephemeris Sky")
                .font(.system(size: 14, weight: .bold))
                .kerning(0.3)
                .foregroundStyle(
                    LinearGradient(colors: [Color(rgbHex: 0xFF4D9D), Color(rgbHex: 0x35E7FF)],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 12)
        }
    }

}
#endif
