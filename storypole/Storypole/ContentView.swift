import SwiftUI

/// Three tabs at compact width, a split view at regular. **Identical behaviour on iPhone, iPad and
/// Mac** — the incumbent's defining failure is that it crashes on iPad
/// (*"it crashes every single time I try to use a fraction on my iPad"*, 2★ 2026-01-10), so parity
/// is the wedge, not a nicety.
struct ContentView: View {
    @EnvironmentObject private var router: Router
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSize
#endif

    var body: some View {
#if os(macOS)
        RegularRoot()
#else
        if hSize == .regular { RegularRoot() } else { tabs }
#endif
    }

    private var tabs: some View {
        TabView(selection: Binding(get: { router.selectedTab },
                                   set: { router.selectedTab = $0 })) {
            NavigationStack { CalcView() }
                .tabItem { Label("Calc", systemImage: "ruler") }
                .tag(0)
            NavigationStack(path: Binding(get: { router.toolPath },
                                          set: { router.toolPath = $0 })) {
                ToolsRootView()
                    .navigationDestination(for: Tool.self) { ToolDetailView(tool: $0) }
            }
            .tabItem { Label("Tools", systemImage: "square.grid.2x2") }
            .tag(1)
            NavigationStack { ReferenceView() }
                .tabItem { Label("Reference", systemImage: "book") }
                .tag(2)
        }
        .background(SP.background)
    }
}

/// iPad and Mac: a sidebar of every tool, the calculator pinned at the top.
struct RegularRoot: View {
    @EnvironmentObject private var router: Router
    @State private var selection: SidebarItem? = .calc

    enum SidebarItem: Hashable {
        case calc, reference, tool(Tool)
    }

    var body: some View {
        NavigationSplitView {
            sidebarList
                // Without a floor the sidebar renders narrow enough to truncate half the tool
                // names — "Miter & Be…", "Circle & Pi…" — which then shipped into a Mac
                // screenshot. The longest name here is "Nominal vs Dressed".
                .navigationSplitViewColumnWidth(min: 238, ideal: 258, max: 320)
        } detail: {
            switch selection {
            case .calc, .none:      CalcView()
            case .reference:        ReferenceView()
            case .tool(let t):      ToolDetailView(tool: t)
            }
        }
        // Honour BOTH deep-link shapes. `STORYPOLE_TOOL` sets `router.sidebar`, but
        // `STORYPOLE_TAB` only ever set `selectedTab` — which this layout has no tabs for, so it
        // was silently ignored and every tab deep link landed on Calc. That shipped a "Reference"
        // screenshot showing the calculator, captioned "Every number has a source".
        .onAppear { syncFromRouter() }
        .onChange(of: router.sidebar) { _, new in if let new { selection = .tool(new) } }
        .onChange(of: router.selectedTab) { _, _ in syncFromRouter() }
    }

    private func syncFromRouter() {
        if let t = router.sidebar { selection = .tool(t) }
        else if router.selectedTab == 2 { selection = .reference }
        else { selection = .calc }
    }

    // Broken out of `body`: inline, the List + nested ForEach + Section + Label pushed the
    // type-checker past its expression limit, and it reported the failure on an unrelated line.
    private var sidebarList: some View {
        List(selection: $selection) {
            Label("Calc", systemImage: "ruler").tag(SidebarItem.calc)
            ForEach(ToolSection.allCases) { section in
                Section {
                    sectionRows(section)
                } header: {
                    Text(L.loc(section.rawValue))
                }
            }
            Label("Reference", systemImage: "book").tag(SidebarItem.reference)
        }
        .navigationTitle("Storypole")
#if os(macOS)
        .listStyle(.sidebar)
#endif
    }

    @ViewBuilder private func sectionRows(_ section: ToolSection) -> some View {
        ForEach(Tool.tools(in: section)) { tool in
            Label {
                Text(tool.title)
            } icon: {
                Image(systemName: tool.symbol).foregroundStyle(section.accent)
            }
            .tag(SidebarItem.tool(tool))
        }
    }
}
