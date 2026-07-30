import SwiftUI

/// The wrist catalog — all 20 calculators, grouped by trade.
///
/// Ported from `overtonelab.swift/OverToneLabWatch/WatchToolList.swift`, which solves the same problem
/// (26 wrist tools) the same way. One `List` with a `Section` per trade rather than two levels of
/// navigation: any tool stays **one tap** away, the crown scrolls the list for free, and the accent
/// headers give you your place in 20 rows. On a wrist you are usually reaching for one specific number
/// fast, so an extra tap per calculation is the wrong trade.
///
/// `Tool.tools(in:)` drives it, so a twenty-first calculator appears here with no edit — the same
/// catalog the phone grid reads.
struct WatchToolList: View {
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        List {
            ForEach(ToolSection.allCases) { section in
                Section {
                    ForEach(Tool.tools(in: section)) { tool in
                        NavigationLink(value: tool) { row(tool, section) }
                            .buttonStyle(.plain)
                            .listRowBackground(
                                RoundedRectangle(cornerRadius: KCW.rCard)
                                    .fill(dimmed ? .clear : KCW.card)
                                    .strokeBorder(dimmed ? .clear : KCW.hairline, lineWidth: 1)
                            )
                    }
                } header: {
                    HStack(spacing: 5) {
                        Capsule().fill(section.accent).frame(width: 3, height: 9)
                        Text(section.rawValue)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(KCW.inkSoft)
                    }
                }
            }
        }
        .listStyle(.carousel)
        .navigationTitle("Kerf Calc")
        .containerBackground(dimmed ? KCW.ambientCanvas : KCW.paper, for: .navigation)
    }

    private func row(_ tool: Tool, _ section: ToolSection) -> some View {
        HStack(spacing: 9) {
            Image(systemName: tool.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(section.accent)
                .frame(width: 19)
            VStack(alignment: .leading, spacing: 0) {
                Text(tool.title)
                    .font(.system(.body, design: .default).weight(.medium))
                    .foregroundStyle(KCW.ink)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(tool.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(KCW.inkSoft)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        // Rows 40 pt, not 44 — at 44 a 40 mm screen fits two tools and a 20-row catalog stops being
        // usable (watch_guidelines §2, deviation 8). Consequential controls stay at 44.
        .frame(minHeight: KCW.row)
        // On the ROW, never on the Section: an identifier on a container overwrites every child's and
        // would leave no row addressable — not by a test and not by VoiceOver.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tool." + tool.rawValue)
    }
}
