import SwiftUI

/// The catalog. Derives entirely from `ToolSection.allCases` × `Tool.tools(in:)`.
///
/// The tile leads with the section colour and a sample value, so a tool is recognisable before it
/// is opened.
struct ToolsRootView: View {
    @State private var query = ""

    private var sections: [(ToolSection, [Tool])] {
        ToolSection.allCases.compactMap { s in
            let tools = Tool.tools(in: s).filter { matches($0) }
            return tools.isEmpty ? nil : (s, tools)
        }
    }

    private func matches(_ t: Tool) -> Bool {
        guard !query.isEmpty else { return true }
        return t.rawValue.localizedCaseInsensitiveContains(query)
            || t.sample.localizedCaseInsensitiveContains(query)
            || String(describing: t.title).localizedCaseInsensitiveContains(query)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: SP.s5) {
                ForEach(sections, id: .0) { section, tools in
                    VStack(alignment: .leading, spacing: SP.s3) {
                        SectionEyebrow(title: section.rawValue, accent: section.accent)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: SP.s3)],
                                  spacing: SP.s3) {
                            ForEach(tools) { tool in
                                NavigationLink(value: tool) { ToolTile(tool: tool) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("tool." + tool.rawValue)
                            }
                        }
                    }
                }
            }
            .padding(SP.s4)
        }
        .background(SP.background)
        .navigationTitle("Tools")
        .searchable(text: $query, prompt: "Find a calculator")
    }
}

struct ToolTile: View {
    let tool: Tool

    var body: some View {
        VStack(alignment: .leading, spacing: SP.s2) {
            HStack(alignment: .top) {
                Image(systemName: tool.symbol)
                    .font(.title3)
                    .foregroundStyle(tool.section.accent)
                Spacer()
                Text(tool.sample)
                    .font(SPType.footnote.monospaced())
                    .foregroundStyle(SP.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: SP.s2)
            Text(tool.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SP.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(tool.subtitle)
                .font(SPType.footnote)
                .foregroundStyle(SP.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
        .spCard(SP.rTile, rule: tool.section.accent)
    }
}

#Preview        { NavigationStack { ToolsRootView() } }
#Preview("Dark") { NavigationStack { ToolsRootView() }.preferredColorScheme(.dark) }
