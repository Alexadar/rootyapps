import SwiftUI

/// Cross-platform root: iPhone (compact) → grouped grid + push nav;
/// iPad landscape / Mac / wide multitasking (regular) → NavigationSplitView.
/// Same tokens & components everywhere — only the container adapts.
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @StateObject private var favorites = FavoritesStore()
    @State private var selection: Tool? = deepLinkTool()
    @State private var path: [Tool] = deepLinkTool().map { [$0] } ?? []
    @State private var showSettings = false

    var body: some View {
        Group {
            #if os(macOS)
            splitView
            #else
            if hSize == .regular {
                splitView
            } else {
                NavigationStack(path: $path) {
                    CatalogGrid(favorites: favorites)
                        .navigationDestination(for: Tool.self) { ToolDetailView(tool: $0) }
                        .toolbar { settingsButton }
                }
            }
            #endif
        }
        .preferredColorScheme(.dark)
        #if os(iOS)
        // On macOS the same screen is the Settings scene (⌘,), wired in OverToneLabApp.
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
                .presentationDetents([.medium])
        }
        #endif
    }

    #if os(iOS)
    private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityIdentifier("settings.open")
        }
    }
    #endif

    private var splitView: some View {
        NavigationSplitView {
            List(selection: $selection) {
                if !favorites.favoriteTools.isEmpty {
                    ToolGroup(title: "Favorites", accent: OTL.star,
                              tools: favorites.favoriteTools, favorites: favorites)
                }
                ForEach(ToolSection.allCases) { section in
                    ToolGroup(title: section.rawValue, accent: section.accent,
                              tools: Tool.tools(in: section), favorites: favorites)
                }
            }
            .navigationTitle("Overtone Lab")
            #if os(iOS)
            .navigationSplitViewColumnWidth(min: 260, ideal: 290)
            .toolbar { settingsButton }
            #endif
        } detail: {
            if let tool = selection {
                ToolDetailView(tool: tool)
            } else {
                ContentUnavailableView("Select a tool", systemImage: "waveform")
            }
        }
    }
}

private func deepLinkTool() -> Tool? {
    ProcessInfo.processInfo.environment["OVERTONELAB_TOOL"].flatMap(Tool.init(rawValue:))
}

/// One sidebar section: a coloured label + tappable rows with a favourite swipe action.
private struct ToolGroup: View {
    let title: String
    let accent: Color
    let tools: [Tool]
    @ObservedObject var favorites: FavoritesStore

    var body: some View {
        Section {
            ForEach(tools) { tool in
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tool.title).font(.body.weight(.semibold))
                        Text(tool.subtitle).font(.caption).foregroundStyle(OTL.textSecondary)
                    }
                } icon: {
                    Image(systemName: tool.symbol).foregroundStyle(tool.accent)
                }
                .tag(tool)
                .swipeActions(edge: .leading) {
                    Button { favorites.toggle(tool) } label: {
                        Image(systemName: favorites.isFavorite(tool) ? "star.slash" : "star")
                    }.tint(OTL.star)
                }
            }
        } header: {
            HStack(spacing: 8) {
                Capsule().fill(accent).frame(width: 4, height: 11)
                // `title` arrives as a String (ToolSection.rawValue / "Favorites"), so it needs
                // L.loc — Text(String) renders verbatim and would ship English.
                Text(L.loc(title)).textCase(.uppercase)
                    .font(.system(.caption2, design: .monospaced).weight(.semibold)).tracking(1.3)
            }
        }
    }
}
