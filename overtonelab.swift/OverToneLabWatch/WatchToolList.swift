import SwiftUI

/// The catalog, as the FIRST page of the same vertical TabView — not a pushed screen.
///
/// The original design paged straight between tools with no way to see what existed. Adding a
/// list as page zero keeps the sweeps exactly as they are: tapping a row jumps paging to that
/// tool, and swiping back up returns here. That is why there is no back button — the gesture
/// that got you here also brings you back.
struct WatchToolList: View {
    @Binding var selection: WatchPage

    var body: some View {
        List {
            ForEach(ToolSection.allCases) { section in
                Section {
                    ForEach(Tool.tools(in: section)) { tool in
                        Button {
                            selection = .tool(tool)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: tool.symbol)
                                    .foregroundStyle(section.accent)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(tool.title)
                                        .font(.system(.body, design: .default).weight(.medium))
                                        .foregroundStyle(OTL.textPrimary)
                                    Text(tool.subtitle)
                                        .font(.system(size: 11))
                                        .foregroundStyle(OTL.textSecondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                            }
                            .padding(.vertical, 1)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 10).fill(OTL.surface)
                        )
                    }
                } header: {
                    // Authored in final case — never .textCase(.uppercase): that maps Greek alpha
                    // in labels like ΣSα onto a glyph-identical Latin A.
                    HStack(spacing: 5) {
                        Capsule().fill(section.accent).frame(width: 3, height: 9)
                        Text(L.loc(section.rawValue))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(OTL.textSecondary)
                    }
                }
            }
        }
        .listStyle(.carousel)
        .containerBackground(OTL.background.gradient, for: .tabView)
    }
}
