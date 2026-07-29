import SwiftUI

/// The shell for every calculator.
///
/// The switch is split across two `@ViewBuilder` functions. A single 16-case switch in one `body`
/// pushes the type-checker past its expression limit and it reports the failure as an unrelated
/// error somewhere else entirely — a lesson already paid for in `overtonelab`.
struct ToolDetailView: View {
    let tool: Tool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SP.s3) {
                header
                content(for: tool)
            }
            .padding(SP.s4)
        }
        .background(SP.background)
        .navigationTitle(tool.title)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .tint(tool.section.accent)
    }

    /// The header wears the section's colour as a top rule, exactly as the tool's tile does in the
    /// catalog — so opening a tool never loses the thread of where it came from.
    private var header: some View {
        HStack(spacing: SP.s3) {
            Image(systemName: tool.symbol)
                .font(.title3)
                .foregroundStyle(tool.section.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.title)
                    .font(SPType.title)
                    .foregroundStyle(SP.textPrimary)
                Text(tool.subtitle)
                    .font(SPType.label)
                    .foregroundStyle(SP.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .spCard(SP.rCard, rule: tool.section.accent)
    }

    @ViewBuilder private func content(for tool: Tool) -> some View {
        switch tool.section {
        case .tape, .layout, .takeoff: firstHalf(tool)
        default:                       secondHalf(tool)
        }
    }

    @ViewBuilder private func firstHalf(_ tool: Tool) -> some View {
        switch tool {
        case .tapeCalc:     CalcView()
        case .convert:      ConvertToolView()
        case .fraction:     FractionToolView()
        case .equalSpacing: EqualSpacingToolView()
        case .onCenter:     OnCenterToolView()
        case .area:         AreaToolView()
        case .volume:       VolumeToolView()
        case .cubicYards:   CubicYardsToolView()
        default:            EmptyView()
        }
    }

    @ViewBuilder private func secondHalf(_ tool: Tool) -> some View {
        switch tool {
        case .roofPitch:    RoofPitchToolView()
        case .rafter:       RafterToolView()
        case .diagonal:     DiagonalToolView()
        case .miter:        MiterToolView()
        case .circle:       CircleToolView()
        case .boardFeet:    BoardFeetToolView()
        case .dressedSize:  DressedSizeToolView()
        case .wireGauge:    WireGaugeToolView()
        default:            EmptyView()
        }
    }
}
