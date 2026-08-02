import SwiftUI

/// The wrist app: the trade-grouped catalog, pushing to one tool at a time.
///
/// All 20 phone calculators are here — `WatchToolList` reads the same `Tool` catalog the phone grid does,
/// and the switch below has a case for every one of them. **There is deliberately no `default:`**: a new
/// calculator then fails to compile here instead of silently becoming a blank screen on the wrist.
///
/// `KERFCALC_TOOL` (a raw `Tool` value) pins the opening screen so a screenshot or a UI test needs one
/// build, not one per screen — the same deep link the phone uses, and DEBUG-only via `LaunchOverride`.
struct WatchRootView: View {
    @State private var path: [Tool] = deepLinkTool().map { [$0] } ?? []

    var body: some View {
        NavigationStack(path: $path) {
            WatchToolList()
                .navigationDestination(for: Tool.self) { screen(for: $0) }
        }
    }

    @ViewBuilder private func screen(for tool: Tool) -> some View {
        switch tool {
        // Framing
        case .rafter:        RafterWatch()
        case .stairs:        StairsWatch()
        case .pitch:         PitchWatch()
        // Concrete
        case .concrete:      ConcreteWatch()
        case .footing:       FootingWatch()
        case .rebar:         RebarWatch()
        case .aggregate:     AggregateWatch()
        case .pavers:        PaversWatch()
        // Takeoff
        case .area:          AreaWatch()
        case .volume:        VolumeWatch()
        // Materials
        case .roofing:       RoofingWatch()
        case .estimate:      EstimateWatch()
        case .miter:         MiterWatch()
        case .lumber:        LumberWatch()
        case .mortar:        MortarWatch()
        // Pipe
        case .offset:        OffsetWatch()
        case .rollingOffset: RollingOffsetWatch()
        case .cutLength:     CutLengthWatch()
        case .grade:         GradeWatch()
        // Convert
        case .units:         ConvertWatch()
        }
    }
}

private func deepLinkTool() -> Tool? {
    // DEBUG-only, same gate as the phone — see KerfCalc/LaunchOverride.swift, compiled into this
    // target too. A shipped watch app must not take its navigation from the environment.
    LaunchOverride.value("KERFCALC_TOOL").flatMap(Tool.init(rawValue:))
}
