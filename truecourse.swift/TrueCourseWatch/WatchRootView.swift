import SwiftUI

/// The wrist catalog — all 9 tools in their 3 `CalcGroup` sections, reusing the phone `Tool` enum
/// (title / symbol / group / accent). `TRUECOURSE_TOOL` (a raw `Tool` value) pins the opening screen
/// for screenshots/verification (DEBUG-only via `LaunchOverride`, same as the phone).
struct WatchRootView: View {
    @Environment(\.tc) private var tc
    @State private var path: [Tool] = deepLinkTool().map { [$0] } ?? []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(CalcGroup.allCases) { group in
                    Section {
                        ForEach(Tool.tools(in: group)) { tool in
                            NavigationLink(value: tool) { WatchToolTile(tool: tool) }
                        }
                    } header: {
                        Text(group.rawValue.uppercased())
                            .font(.system(size: 10, design: .monospaced).weight(.semibold)).tracking(1.0)
                            .foregroundStyle(tc.accent(group))
                    }
                }
            }
            .navigationTitle("TrueCourse")
            .containerBackground(tc.background, for: .navigation)
            .navigationDestination(for: Tool.self) { screen(for: $0) }
        }
    }

    @ViewBuilder private func screen(for tool: Tool) -> some View {
        switch tool {
        case .wind:     WindWatch()
        case .airspeed: AirspeedWatch()
        case .altitude: AltitudeWatch()
        case .nav:      NavWatch()
        case .fuel:     FuelWatch()
        case .climb:    ClimbWatch()
        case .wb:       WBWatch()
        case .convert:  ConvertWatch()
        case .timer:    TimerWatch()
        }
    }
}

private func deepLinkTool() -> Tool? {
    LaunchOverride.value("TRUECOURSE_TOOL").flatMap(Tool.init(rawValue:))
}
