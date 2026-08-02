import SwiftUI

/// The catalog — the app's other half. Tap a row, get that tool; swipe left-to-right or tap the
/// tool's header to come back. Nothing pages between tools any more, so the crown belongs to the
/// fields and this list is the only way to change which tool you are on.
struct WatchToolList: View {
    @Binding var selection: WatchPage

    var body: some View {
        List {
            ForEach(ToolSection.allCases) { section in
                Section {
                    ForEach(Tool.tools(in: section)) { tool in
                        Button {
                            withAnimation { selection = .tool(tool) }
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
                        // On the row's Button, not on the Section: an identifier on the container
                        // would overwrite every child's and leave no row addressable.
                        .accessibilityIdentifier("tool.\(tool.rawValue)")
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
        .background(OTL.background.ignoresSafeArea())
    }
}
