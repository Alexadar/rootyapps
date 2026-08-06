import SwiftUI

/// Cross-platform root: iPhone (compact) → grouped grid + push nav;
/// iPad landscape / Mac / wide multitasking (regular) → NavigationSplitView.
/// Same tokens & components everywhere — only the container adapts.
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @StateObject private var favorites = FavoritesStore()
    /// Siblings of `FavoritesStore`, and that placement is the whole navigation design: a measurement
    /// lives OUTSIDE the stack, so popping Analysis discards a view and not a session. Measure once,
    /// visit three calculators, come back — still there.
    @StateObject private var measurements = MeasurementStore()
    @StateObject private var provenance = FieldProvenance()
    @StateObject private var handoff = MeasurementHandoff()
    @State private var selection: CatalogEntry? = deepLinkEntry()
    @State private var path: [CatalogEntry] = deepLinkEntry().map { [$0] } ?? []
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
                        .navigationDestination(for: CatalogEntry.self) { destination(for: $0) }
                        // Send rows push a Tool directly, so both value types must be handled.
                        .navigationDestination(for: Tool.self) { ToolDetailView(tool: $0) }
                        .toolbar { settingsButton }
                }
            }
            #endif
        }
        .environmentObject(measurements)
        .environmentObject(provenance)
        .environmentObject(handoff)
        // Receive, never capture: the phone publishes its session and the watch renders it. One
        // direction, whole payload, latest value wins.
        .task { SessionTransport.shared.activate() }
        .onChange(of: measurements.session) { _, session in SessionTransport.shared.send(session) }
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
                // On a released SDK `CatalogEntry.sources` is empty, so this whole Section is absent —
                // no header, no greyed row, nothing reflows.
                if !CatalogEntry.sources.isEmpty {
                    Section {
                        ForEach(CatalogEntry.sources) { entry in
                            SourceRow(entry: entry).tag(entry)
                        }
                    } header: {
                        SidebarLabel(title: "Sources", accent: OTL.measureAccent)
                    }
                }
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
            if let selection {
                destination(for: selection)
            } else {
                ContentUnavailableView("Select a tool", systemImage: "waveform")
            }
        }
    }

    @ViewBuilder private func destination(for entry: CatalogEntry) -> some View {
        switch entry {
        case .tool(let tool):       ToolDetailView(tool: tool)
        case .source(.measure):     MeasureView()
        }
    }
}

/// `OVERTONELAB_TOOL=<t>` opens a tool; `OVERTONELAB_MEASURE=1` alone opens Analysis.
private func deepLinkEntry() -> CatalogEntry? {
    // `OVERTONELAB_TOOL=<t>&measured=1` — the suffix marks the handoff for tests; the tool id is
    // everything before the ampersand.
    if let raw = LaunchOverride.value("OVERTONELAB_TOOL") {
        let id = raw.split(separator: "&").first.map(String.init) ?? raw
        if let tool = Tool(rawValue: id) { return .tool(tool) }
    }
    if LaunchOverride.flag("OVERTONELAB_MEASURE"), let source = CatalogEntry.sources.first {
        return source
    }
    return nil
}

/// A sidebar section header, matching `ToolGroup`'s.
private struct SidebarLabel: View {
    let title: LocalizedStringKey
    let accent: Color
    var body: some View {
        HStack(spacing: 8) {
            Capsule().fill(accent).frame(width: 4, height: 11)
            Text(title).textCase(.uppercase)
                .font(.system(.caption2, design: .monospaced).weight(.semibold)).tracking(1.3)
        }
    }
}

private struct SourceRow: View {
    let entry: CatalogEntry
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text("Measure").font(.body.weight(.semibold))
                Text("Analyse audio, hand values over")
                    .font(.caption).foregroundStyle(OTL.textSecondary)
            }
        } icon: {
            Image(systemName: "waveform.badge.mic").foregroundStyle(OTL.measureAccent)
        }
        .accessibilityIdentifier("catalog.measure")
    }
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
                // Tagged as a CatalogEntry, because the sidebar's selection now holds sources too.
                .tag(CatalogEntry.tool(tool))
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
