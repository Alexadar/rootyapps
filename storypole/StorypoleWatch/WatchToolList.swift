import SwiftUI

/// The catalog — seven tools, not sixteen. Tap a row to get that tool; swipe left-to-right or tap
/// the header to come back.
struct WatchToolList: View {
    @Binding var selection: WatchPage

    var body: some View {
        List {
            ForEach(ToolSection.allCases.filter { !Tool.tools(in: $0).filter(\.onWatch).isEmpty }) { section in
                Section {
                    ForEach(Tool.tools(in: section).filter(\.onWatch)) { tool in
                        Button {
                            withAnimation { selection = .tool(tool) }
                        } label: {
                            HStack(spacing: SP.s2) {
                                Image(systemName: tool.symbol)
                                    .foregroundStyle(section.accent)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(tool.title)
                                        .font(.system(.body, design: .default).weight(.medium))
                                        .foregroundStyle(SP.textPrimary)
                                    Text(tool.subtitle)
                                        .font(.system(size: 11))
                                        .foregroundStyle(SP.textSecondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                            }
                            .padding(.vertical, 1)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(RoundedRectangle(cornerRadius: SP.rChip).fill(SP.surface))
                    }
                } header: {
                    // Authored in final case — never .textCase(.uppercase).
                    HStack(spacing: SP.s1) {
                        Capsule().fill(section.accent).frame(width: 3, height: 9)
                        Text(L.loc(section.rawValue))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(SP.textSecondary)
                    }
                }
            }
        }
        .listStyle(.carousel)
        .background(SP.background.ignoresSafeArea())
    }
}
