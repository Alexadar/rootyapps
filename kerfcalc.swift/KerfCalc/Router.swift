import SwiftUI

/// App-level navigation state so the Spec keypad's nav keys (Rafter/Stair/Area/Vol) can open a
/// formula screen on the Formulas tab, and deep-link envs seed the launch surface.
@MainActor
final class Router: ObservableObject {
    /// Compact tab. A `KERFCALC_TOOL` deep link must land on the Formulas tab, not just push the tool
    /// onto an unselected stack — otherwise the tool is invisible on iPhone and the launch shows Spec.
    @Published var selectedTab: Int = launchTool() != nil ? 1 : launchTab()
    @Published var formulasPath: [Tool] = launchTool().map { [$0] } ?? []
    /// Sidebar selection for the regular-size-class split view.
    @Published var sidebar: SidebarItem? = launchTool().map(SidebarItem.tool) ?? .spec

    /// Regular-size root state: which of the three surfaces the rail shows, and — for Formulas —
    /// which trade the category sidebar has selected (nil = All). Reference has its own section.
    @Published var surface: Surface = launchTool() != nil ? .formulas : (Surface(rawValue: launchTab()) ?? .spec)
    @Published var category: ToolSection? = launchTool()?.section
    @Published var refSection: ReferenceSection? = nil

    enum Surface: Int, CaseIterable { case spec = 0, formulas = 1, reference = 2 }
    enum SidebarItem: Hashable { case spec, reference, tool(Tool) }

    /// Open a tool's formula screen (used by the Spec nav keys and deep links). Drives both layouts.
    func open(_ tool: Tool) {
        selectedTab = 1                                   // Formulas tab (compact)
        surface = .formulas                               // Formulas surface (regular)
        category = tool.section
        if formulasPath.last != tool { formulasPath.append(tool) }
        sidebar = .tool(tool)
    }
}

// DEBUG-only: `LaunchOverride` compiles to nil in Release, so a shipped app cannot have its
// navigation driven from outside it. See LaunchOverride.swift.
func launchTab() -> Int { Int(LaunchOverride.value("KERFCALC_TAB") ?? "0") ?? 0 }
func launchTool() -> Tool? { LaunchOverride.value("KERFCALC_TOOL").flatMap(Tool.init(rawValue:)) }
