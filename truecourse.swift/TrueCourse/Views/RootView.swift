import SwiftUI

/// Cross-platform root: iPhone (compact) → grouped instrument grid + push nav;
/// iPad landscape / Mac / wide multitasking (regular) → NavigationSplitView.
/// One design language everywhere; a single toolbar toggle flips Dark ↔ Night.
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var theme = ThemeStore()
    @State private var selection: Tool? = deepLinkTool()
    @State private var path: [Tool] = deepLinkTool().map { [$0] } ?? []
    @State private var columns = NavigationSplitViewVisibility.all   // never collapse on iPad portrait

    var body: some View {
        content
            .tcTheme(theme.selected)              // one line themes everything (Dark / Night)
    }

    @ViewBuilder private var content: some View {
        #if os(macOS)
        splitView
        #else
        if hSize == .regular {
            splitView
        } else {
            NavigationStack(path: $path) {
                CatalogGrid(favorites: favorites)
                    .navigationDestination(for: Tool.self) { ToolDetailView(tool: $0) }
                    .toolbar { ToolbarItem(placement: .primaryAction) { nightToggle } }
            }
        }
        #endif
    }

    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columns) {
            List(selection: $selection) {
                if !favorites.favoriteTools.isEmpty {
                    ToolGroup(title: "Favorites", pinnedAccent: .star,
                              tools: favorites.favoriteTools, favorites: favorites)
                }
                ForEach(CalcGroup.allCases) { group in
                    ToolGroup(title: group.rawValue, group: group,
                              tools: Tool.tools(in: group), favorites: favorites)
                }
            }
            .backgroundExtensionEffect()          // Liquid Glass sidebar carries beyond the safe area
            .navigationTitle("TrueCourse")
            .toolbar { ToolbarItem(placement: .primaryAction) { nightToggle } }
            #if os(iOS)
            .navigationSplitViewColumnWidth(min: 280, ideal: 300)
            #endif
        } detail: {
            if let tool = selection {
                ToolDetailView(tool: tool)
            } else {
                ContentUnavailableView("Select a tool", systemImage: "location.north.line")
            }
        }
        .navigationSplitViewStyle(.balanced)      // keep both columns in iPad portrait
    }

    private var nightToggle: some View {
        Button {
            withAnimation(.smooth) { theme.toggle() }
        } label: {
            Image(systemName: theme.selected == .night ? "moon.stars.fill" : "sun.max.fill")
        }
        .help("Night (red-shift) mode")
        .accessibilityLabel("Night mode")
        .accessibilityValue(theme.selected == .night ? "on" : "off")
        .accessibilityIdentifier("nightToggle")
    }
}

private func deepLinkTool() -> Tool? {
    ProcessInfo.processInfo.environment["TRUECOURSE_TOOL"].flatMap(Tool.init(rawValue:))
}

/// Sidebar accent source: an explicit pinned colour (Favorites) or the group accent.
private enum GroupAccent { case star, group(CalcGroup) }

/// One sidebar section: a coloured label + tappable rows with a favourite swipe action.
private struct ToolGroup: View {
    @Environment(\.tc) private var tc
    let title: String
    var pinnedAccent: GroupAccent? = nil
    var group: CalcGroup? = nil
    let tools: [Tool]
    @ObservedObject var favorites: FavoritesStore

    init(title: String, pinnedAccent: GroupAccent, tools: [Tool], favorites: FavoritesStore) {
        self.title = title; self.pinnedAccent = pinnedAccent; self.tools = tools; self.favorites = favorites
    }
    init(title: String, group: CalcGroup, tools: [Tool], favorites: FavoritesStore) {
        self.title = title; self.group = group; self.tools = tools; self.favorites = favorites
    }

    private var headerAccent: Color {
        if case .star = pinnedAccent { return tc.star }
        return group.map { tc.accent($0) } ?? tc.brand
    }

    var body: some View {
        Section {
            ForEach(tools) { tool in
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tool.title).font(.body.weight(.semibold))
                        Text(tool.subtitle).font(.caption).foregroundStyle(tc.textSecondary)
                    }
                } icon: {
                    Image(systemName: tool.symbol).foregroundStyle(tc.accent(tool.group))
                }
                .tag(tool)
                .swipeActions(edge: .leading) {
                    Button { favorites.toggle(tool) } label: {
                        Image(systemName: favorites.isFavorite(tool) ? "star.slash" : "star")
                    }.tint(tc.star)
                }
            }
        } header: {
            SectionLabel(title: title, accent: headerAccent)
        }
    }
}
