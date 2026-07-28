import SwiftUI

/// Root navigation: a split view on regular width (iPad, Mac), a stack on
/// compact (iPhone).
///
/// The structural seams that used to live here — `ToolSection`, `ResultRow`,
/// `NumberField`, `ProvenanceFooter` — have moved to `DesignSystem.swift`, with
/// the same call-site shapes. This file now owns only the root: navigation, the
/// tool catalog rows, and the appearance mode.
struct ContentView: View {
    @State private var selection: Tool? = ContentView.initialTool
    @AppStorage("marine.mode") private var modeRaw: String = MarineMode.auto.rawValue
    @Environment(\.colorScheme) private var systemScheme

    private var mode: MarineMode { MarineMode(rawValue: modeRaw) ?? .auto }
    private var theme: MarineTheme { MarineTheme(mode: mode, systemScheme: systemScheme) }
    private var palette: MarinePalette { theme.palette }

    /// Lets a capture run open straight onto one tool:
    /// `xcrun simctl launch <sim> <bundle> -tool declination`.
    /// Capture/automation affordance only — no product behaviour depends on it.
    static var initialTool: Tool {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-tool"), i + 1 < args.count,
           let t = Tool(rawValue: args[i + 1]) {
            return t
        }
        return .tides
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let selection {
                selection.destination
                    .navigationTitle(selection.title)
            } else {
                ContentUnavailableView("Choose a tool", systemImage: "sailboat")
                    .background(palette.canvas)
            }
        }
        .environment(\.marine, theme)
        .tint(palette.water)
        .preferredColorScheme(mode == .auto ? nil : palette.colorScheme)
    }

    // MARK: Sidebar
    //
    // Still a List of `Tool.allCases` carrying `tool.<rawValue>` identifiers:
    // ReelTour taps these rows and then taps the navigation-bar back button, so
    // the drill-down structure is load-bearing for the App Store capture and is
    // deliberately NOT replaced with a tab bar.

    private var sidebar: some View {
        List(Tool.allCases, selection: $selection) { tool in
            NavigationLink(value: tool) {
                HStack(spacing: 11) {
                    Image(systemName: tool.symbol)
                        .font(.system(size: 16))
                        .frame(width: 24)
                        .foregroundStyle(selection == tool ? palette.water : palette.inkDim)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tool.title)
                            .font(.system(size: 15, weight: selection == tool ? .semibold : .medium))
                            .foregroundStyle(palette.ink)
                        Text(tool.subtitle)
                            .font(MarineType.caption)
                            .foregroundStyle(palette.inkDim)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityIdentifier("tool.\(tool.rawValue)")
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: MarineMetrics.controlRadius, style: .continuous)
                    .fill(selection == tool ? palette.surface : .clear)
                    .strokeBorder(selection == tool ? palette.hairline : .clear, lineWidth: 1)
                    .padding(.horizontal, 6)
            )
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(palette.chrome)
        .safeAreaInset(edge: .bottom) { sidebarFooter }
        .navigationTitle("Marine Nav")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar { modeMenu }
    }

    /// Provenance is product surface: the three differentiators App Review 4.3(b)
    /// wants to see are pinned to the root, not buried per screen.
    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(["Works with no signal",
                     "Validated against NOAA",
                     "Bought once · no subscription"], id: \.self) { line in
                Text(line.uppercased())
                    .font(MarineType.badge)
                    .tracking(0.7)
                    .foregroundStyle(palette.water)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(palette.water.opacity(0.09),
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(palette.water.opacity(0.22), lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(palette.chrome)
        .overlay(alignment: .top) { palette.hairline.frame(height: 1) }
    }

    private var modeMenu: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Appearance", selection: $modeRaw) {
                    ForEach(MarineMode.allCases) { m in
                        Label(m.title, systemImage: m.symbol).tag(m.rawValue)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: mode.symbol)
            }
            .accessibilityIdentifier("input.appearance")
        }
    }
}

#Preview("Catalog — day") {
    ContentView()
}

#Preview("Catalog — night") {
    ContentView()
        .environment(\.marine, MarineTheme(mode: .nightRed))
}
