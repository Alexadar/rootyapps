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
    @State private var selection = LaunchOverride.int("EPHEMERIS_TAB") ?? 0

    private let tabs: [MacTab] = [
        .init(id: 0, title: "Chart",     icon: "circle.hexagongrid"),
        .init(id: 1, title: "Positions", icon: "list.star"),
        .init(id: 2, title: "Aspects",   icon: "point.3.connected.trianglepath.dotted"),
        .init(id: 3, title: "Cycle",     icon: "arrow.triangle.2.circlepath"),
        .init(id: 4, title: "Events",    icon: "calendar"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) { content }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
        }
        .background(AppBackground())
        .navigationTitle("Ephemeris Sky")
        .toolbar {
            // Section navigator — a single Liquid Glass capsule of icon buttons.
            ToolbarItemGroup(placement: .principal) {
                ForEach(tabs) { tab in
                    let selected = tab.id == selection
                    Button {
                        withAnimation(.smooth(duration: 0.35)) { selection = tab.id }
                    } label: {
                        // A filled magenta pill marks the active section — toolbar `.tint`
                        // alone is nearly invisible (and several of these symbols have no
                        // distinct `.fill` variant), so highlight the selection explicitly.
                        Label(tab.title, systemImage: tab.icon)
                            .labelStyle(.iconOnly)
                            .symbolVariant(selected ? .fill : .none)
                            .font(.system(size: 14, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? NebulaPalette.accent : NebulaPalette.textSecondary)
                            .frame(width: 32, height: 26)
                            .background(selected ? NebulaPalette.accent.opacity(0.18) : .clear, in: .capsule)
                            .overlay {
                                if selected {
                                    Capsule().stroke(NebulaPalette.accent.opacity(0.55), lineWidth: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(tab.title)
                }
            }
        }
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
        switch selection {
        case 0:
            MomentControls(vm: vm)
            ChartWheel(positions: vm.positions, aspects: vm.aspects, houses: vm.houses)
                .onAppear { vm.startChartDemo() }
                .onDisappear { vm.stopChartDemo() }
            HousesCard(vm: vm)
        case 1:
            MomentControls(vm: vm)
            PositionsTable(positions: vm.positions)
        case 2:
            AspectsList(aspects: vm.aspects)
        case 3:
            CycleView(vm: vm)
        default:
            EventsView(events: vm.timelineEvents, now: vm.instant)
        }
    }
}
#endif
