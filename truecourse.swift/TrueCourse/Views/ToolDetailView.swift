import SwiftUI

struct ToolDetailView: View {
    @Environment(\.tc) private var tc
    let tool: Tool
    var body: some View {
        ScrollView {
            VStack(spacing: 16) { content }
                .frame(maxWidth: 980)            // room for inputs | readout side by side
                .frame(maxWidth: .infinity)
                .padding(TC.screenMargin)
        }
        #if os(iOS)
        .scrollEdgeEffectStyle(.soft, for: .all)   // content fades under the translucent glass bar
        #endif
        .background(AppBackground(accent: tc.accent(tool.group)))
        .tint(tc.accent(tool.group))             // flows to hero ResultRow + pill segmented control
        .navigationTitle(tool.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder private var content: some View {
        switch tool {
        case .wind:     WindToolView()
        case .airspeed: AirspeedToolView()
        case .altitude: AltitudeToolView()
        case .nav:      NavToolView()
        case .fuel:     FuelToolView()
        case .climb:    ClimbToolView()
        case .wb:        WeightBalanceToolView()
        case .convert:  ConvertToolView()
        case .timer:    TimerToolView()
        }
    }
}

/// Initial sub-screen from the screenshot env hook (shared across tools; one launch at a time).
func initialScreen() -> Int { Int(ProcessInfo.processInfo.environment["TRUECOURSE_SCREEN"] ?? "0") ?? 0 }
