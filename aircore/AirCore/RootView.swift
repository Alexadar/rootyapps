import SwiftUI
import UnitsKit

/// Navigation.
///
/// A catalogue on the phone, a sidebar everywhere else — chosen on width rather than on device, so
/// an iPad in a narrow Split View behaves like the phone it is currently the size of.
struct RootView: View {

    @Environment(AppSettings.self) private var settings
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    @State private var selection: Tool? = RootView.deepLinkedTool ?? .psychrometrics
    @State private var path: [Tool] = RootView.deepLinkedTool.map { [$0] } ?? []

    /// `AIRCORE_TOOL=duct` opens that tool directly.
    ///
    /// The UI suite and the capture scripts both need to land on a screen deterministically rather
    /// than scroll-hunting a grid that grows. Debug-only, via ``LaunchOverride`` — see uitests.md
    /// §4b for why a shipping deep link is a real problem and not a tidiness one.
    static var deepLinkedTool: Tool? {
        LaunchOverride.value("AIRCORE_TOOL").flatMap(Tool.init(rawValue:))
    }

    var body: some View {
        #if os(iOS)
        if sizeClass == .compact {
            catalogueStack
        } else {
            splitView
        }
        #else
        splitView
        #endif
    }

    // MARK: - Phone

    private var catalogueStack: some View {
        // A `[Tool]` path rather than `NavigationPath`, so the deep link can seed it directly and
        // the test lands on the tool's detail rather than merely selecting it.
        NavigationStack(path: $path) {
            CatalogueView()
                .navigationDestination(for: Tool.self) { ToolDetailView(tool: $0) }
        }
    }

    // MARK: - iPad and Mac

    private var splitView: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(ToolSection.allCases) { section in
                    Section(section.rawValue) {
                        ForEach(Tool.tools(in: section)) { tool in
                            Label {
                                Text(tool.title)
                            } icon: {
                                Image(systemName: tool.symbol)
                            }
                            .tag(tool)
                            .accessibilityIdentifier("sidebar.\(tool.rawValue)")
                        }
                    }
                }
            }
            .navigationTitle("AirCore")
            .frame(minWidth: 220)
        } detail: {
            if let selection {
                ToolDetailView(tool: selection)
            } else {
                ContentUnavailableView("Pick a tool", systemImage: "square.grid.2x2")
            }
        }
    }
}

/// The phone's home screen: recents first, then everything.
struct CatalogueView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showElevationSheet = false

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: DS.s4) {
                if !settings.recentTools.isEmpty {
                    section("RECENT", tools: settings.recentTools)
                }
                ForEach(ToolSection.allCases) { toolSection in
                    section(toolSection.rawValue.uppercased(),
                            tools: Tool.tools(in: toolSection))
                }
                Text("Everything on this screen is computed on the device from published physics. "
                     + "No account, no network — it works the same in Airplane Mode.")
                    .font(DS.ui(11.5))
                    .foregroundStyle(DS.ink2)
                    .padding(.top, DS.s2)
            }
            .padding(DS.s4)
        }
        .background(DS.breeze)
        .navigationTitle("AirCore")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: DS.s2) {
                    AltitudeChip(elevationMetres: settings.elevationMetres,
                                 system: settings.unitSystem) { showElevationSheet = true }
                    UnitToggle(system: $settings.unitSystem)
                }
            }
        }
        .sheet(isPresented: $showElevationSheet) { ElevationSheet() }
    }

    private func section(_ title: String, tools: [Tool]) -> some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            Text(title)
                .font(DS.ui(10.5, .semibold)).tracking(1)
                .foregroundStyle(DS.ink2)
            // Past XL a two-column grid cannot hold a tool name and its subtitle at a legible
            // size, so it becomes one column rather than truncating the words.
            LazyVGrid(columns: typeSize >= .accessibility1
                        ? [GridItem(.flexible())]
                        : [GridItem(.flexible()), GridItem(.flexible())],
                      spacing: DS.s2) {
                ForEach(tools) { tool in
                    NavigationLink(value: tool) { ToolCard(tool: tool) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ToolCard: View {
    let tool: Tool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            Image(systemName: tool.symbol)
                .font(.system(size: 20))
                .foregroundStyle(DS.water)
                .accessibilityHidden(true)
            Text(tool.title)
                .font(DS.ui(15, .semibold))
                .foregroundStyle(DS.ink)
            Text(tool.subtitle)
                .font(DS.ui(11.5))
                .foregroundStyle(DS.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: DS.hitTarget + 34, alignment: .topLeading)
        .padding(DS.s3 + 2)
        .background(DS.card)
        .overlay(RoundedRectangle(cornerRadius: DS.radiusCard + 2).stroke(DS.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusCard + 2))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tool.\(tool.rawValue)")
    }
}

/// Which screen a tool opens.
struct ToolDetailView: View {
    let tool: Tool

    var body: some View {
        switch tool {
        case .psychrometrics: PsychrometricsView()
        case .airsideHeat:    HeatView()
        case .mixing:         MixingView()
        case .duct:           DuctView()
        case .fan:            FanView()
        case .pipe:           PipeView()
        }
    }
}

/// The elevation chip and unit toggle, in every tool's toolbar.
struct ToolHeader: ToolbarContent {
    @Environment(AppSettings.self) private var settings
    @Binding var showElevationSheet: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            @Bindable var settings = settings
            HStack(spacing: DS.s2) {
                AltitudeChip(elevationMetres: settings.elevationMetres,
                             system: settings.unitSystem) { showElevationSheet = true }
                UnitToggle(system: $settings.unitSystem)
            }
        }
    }
}
