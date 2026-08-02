import SwiftUI

/// One navigation state driving BOTH layouts, so a deep link lands correctly whether the app is
/// showing tabs (compact) or a split view (regular). kerfcalc learned this the hard way: seeding a
/// `NavigationStack` path without also selecting its tab pushes onto a stack nobody can see.
@MainActor
final class Router: ObservableObject {
    @Published var selectedTab: Int
    @Published var toolPath: [Tool] = []
    @Published var sidebar: Tool?

    init() {
        // Capture/UI-test deep links, matching kerfcalc's KERFCALC_TOOL convention.
        // DEBUG-only: `LaunchOverride` compiles to nil in Release, so a shipped app cannot have
        // its navigation driven from outside it. See LaunchOverride.swift.
        if let raw = LaunchOverride.value("STORYPOLE_TOOL"), let tool = Tool(rawValue: raw) {
            selectedTab = 1
            toolPath = [tool]
            sidebar = tool
        } else {
            selectedTab = Int(LaunchOverride.value("STORYPOLE_TAB") ?? "") ?? 0
        }
    }

    func open(_ tool: Tool) {
        selectedTab = 1
        toolPath = [tool]
        sidebar = tool
    }
}
