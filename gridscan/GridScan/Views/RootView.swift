import SwiftUI

// One app, three canvases. Same four sections, same order, same symbols everywhere.
// iPhone (compact): TabView · iPad regular + Mac: sidebar. A month-long iPhone user
// opening the Mac app should be surprised by nothing.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case library, search, destinations, activity

    var id: String { rawValue }
    var title: String {
        switch self {
        case .library: return "Library"
        case .search: return "Search"
        case .destinations: return "Destinations"
        case .activity: return "Activity"
        }
    }
    var symbol: String {
        switch self {
        case .library: return "books.vertical"
        case .search: return "magnifyingglass"
        case .destinations: return "arrow.up.right.square"
        case .activity: return "clock"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var section: AppSection = RootView.deepLinkSection() ?? .library

    var body: some View {
#if os(macOS)
        splitView
#else
        if hSize == .regular {
            splitView
        } else {
            tabView
        }
#endif
    }

    private var tabView: some View {
        TabView(selection: $section) {
            ForEach(AppSection.allCases) { s in
                Tab(s.title, systemImage: s.symbol, value: s) {
                    NavigationStack { sectionView(s) }
                }
            }
        }
    }

    private var splitView: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: sidebarSelection) { s in
                Label(s.title, systemImage: s.symbol)
                    .tag(s)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
            .navigationTitle("GridScan")
        } detail: {
            NavigationStack { sectionView(section) }
        }
    }

    private var sidebarSelection: Binding<AppSection?> {
        Binding(get: { section }, set: { section = $0 ?? .library })
    }

    @ViewBuilder
    private func sectionView(_ s: AppSection) -> some View {
        switch s {
        case .library: LibraryView()
        case .search: SearchView()
        case .destinations: DestinationsView()
        case .activity: ActivityView()
        }
    }

    /// Deep-link hook — must work in BOTH layouts (compact tab AND sidebar), which is
    /// why it seeds the single `section` state both containers read.
    static func deepLinkSection() -> AppSection? {
        LaunchOverride.value("GRIDSCAN_TAB").flatMap(AppSection.init(rawValue:))
    }
}
