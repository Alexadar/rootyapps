import SwiftUI

/// Tool detail shell — section-accent tint, the tool's own inputs/outputs, then the FormulaCard
/// (formula + cited standard + VERIFIED badge). The accent flows from one `.tint(tool.accent)`.
struct ToolDetailView: View {
    let tool: Tool
    @Environment(\.horizontalSizeClass) private var hSize
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                content
                FormulaCard(formula: tool.formula, citation: tool.citation, example: tool.example)
            }
            .frame(maxWidth: hSize == .regular ? 980 : 640)   // regular: room for the two columns
            .frame(maxWidth: .infinity)
            .padding()
        }
        .background(AppBackground(accent: tool.accent))
        .tint(tool.accent)
        .navigationTitle(tool.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder private var content: some View {
        switch tool {
        case .rafter: RafterToolView()
        case .stairs: StairsToolView()
        case .pitch: PitchToolView()
        case .concrete: ConcreteToolView()
        case .footing: FootingToolView()
        case .rebar: RebarToolView()
        case .aggregate: AggregateToolView()
        case .pavers: PaversToolView()
        case .area: AreaToolView()
        case .volume: VolumeToolView()
        case .roofing: RoofingToolView()
        case .estimate: EstimateToolView()
        case .miter: MiterToolView()
        case .lumber: LumberToolView()
        case .mortar: MortarToolView()
        case .units: UnitsToolView()
        }
    }
}
