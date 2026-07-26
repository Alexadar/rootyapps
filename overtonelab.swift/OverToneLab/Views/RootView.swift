import SwiftUI

/// Cross-platform root: iPhone (compact) → grouped grid + push nav;
/// iPad landscape / Mac / wide multitasking (regular) → NavigationSplitView.
/// Same tokens & components everywhere — only the container adapts.
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @StateObject private var favorites = FavoritesStore()
    @State private var selection: Tool? = deepLinkTool()
    @State private var path: [Tool] = deepLinkTool().map { [$0] } ?? []

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
                }
            }
            #endif
        }
        .preferredColorScheme(.dark)
    }

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
                Text(title.uppercased())
                    .font(.system(.caption2, design: .monospaced).weight(.semibold)).tracking(1.3)
            }
        }
    }
}
