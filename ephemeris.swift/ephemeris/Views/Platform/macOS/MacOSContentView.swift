#if os(macOS)
import SwiftUI
import EphemerisKit

private struct MacTab: Identifiable {
    let id: Int
    let title: String
    let icon: String
}

struct MacOSContentView: View {
    @StateObject private var vm = ChartViewModel()
    // Lets screenshot tooling open a specific section via EPHEMERIS_TAB.
    @State private var selection = Int(ProcessInfo.processInfo.environment["EPHEMERIS_TAB"] ?? "0") ?? 0

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
                        Label(tab.title, systemImage: tab.icon)
                            .symbolVariant(selected ? .fill : .none)
                    }
                    .help(tab.title)
                    .tint(selected ? .accentColor : .secondary)
                }
            }
        }
        .preferredColorScheme(.dark)   // celestial UI is always dark — keeps glass + text legible
        .frame(minWidth: 820, minHeight: 640)
    }

    @ViewBuilder private var content: some View {
        switch selection {
        case 0:
            MomentControls(vm: vm)
            ChartWheel(positions: vm.positions, aspects: vm.aspects)
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
