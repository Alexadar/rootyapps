import SwiftUI

// Cross-platform root: iPhone (compact) → stacked grid + push nav;
// iPad landscape / Mac / iPad multitasking (regular) → NavigationSplitView.
// Same tokens & components everywhere — only the container adapts.
// Adapt into RootCatalogView.swift / ContentView.swift.

struct RootViewExample: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @StateObject private var favorites = FavoritesStore()
    @State private var selection: Tool? = nil

    var body: some View {
        #if os(macOS)
        splitView                        // Mac is always regular width
        #else
        if hSize == .regular {
            splitView                    // iPad landscape / multitasking
        } else {
            NavigationStack {            // iPhone / compact iPad
                CatalogGridExample()     // full-screen grouped grid, pushes to detail
                    .navigationDestination(for: Tool.self) { ToolDetailView(tool: $0) }
            }
        }
        #endif
    }

    private var splitView: some View {
        NavigationSplitView {
            // Sidebar: Favorites group + section groups, one row per tool.
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
                ToolDetailView(tool: tool)          // reuses the shared detail
                    .tint(tool.accent)              // accent flows to ResultRow + picker
                    .background(AppBackground(accent: tool.accent))
            } else {
                ContentUnavailableView("Select a tool", systemImage: "waveform")
            }
        }
    }
}

/// One sidebar section: a coloured label + tappable rows with a favourite star.
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
