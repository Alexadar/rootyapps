import SwiftUI

// Reference tab, adaptive:
//   • Compact  → chip filter (All / Codes / Tables / Convert / Standards) + stacked cards.
//   • Regular  → the sidebar owns the section choice; content is a two-column board —
//                short constant cards left, the rafter table + standards ledger right.
// Every card keeps its citation line. Restyle of ReferenceView.swift.

struct ReferenceViewExample: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var section: ReferenceSection? = nil   // nil = All

    private func shows(_ s: ReferenceSection) -> Bool { section == nil || section == s }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Reference").font(.system(size: 30, weight: .heavy)).kerning(-0.4)
                    Text("The cited constants under every calc.")
                        .font(.subheadline).foregroundStyle(KC.textSecondary)
                }

                if hSize == .compact {
                    CategoryChips(items: CategoryChips.referenceItems(), selection: $section)
                }

                if hSize == .regular {
                    // two-column board
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 14) {
                            if shows(.codes) { stairCodes }
                            if shows(.conversions) { conversions }
                            if shows(.tables) { bagYield }
                        }
                        VStack(spacing: 14) {
                            if shows(.tables) { rafterTable }
                            if shows(.standards) { standards }
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    if shows(.codes) { stairCodes }
                    if shows(.tables) { rafterTable }
                    if shows(.conversions) { conversions }
                    if shows(.tables) { bagYield }
                    if shows(.standards) { standards }
                }

                disclaimer
            }
            .frame(maxWidth: 1100).frame(maxWidth: .infinity).padding(16)
        }
        .background(AppBackground())
    }

    // MARK: cards (content unchanged from ReferenceView.swift — presentation only)

    private var stairCodes: some View {
        VStack(spacing: 10) {
            CardHeader(title: "Stair code limits", trailing: "IRC / IBC")
            ResultRow(label: "IRC 2021 max riser", value: "7 3/4", unit: "in")
            ResultRow(label: "IRC 2021 min tread", value: "10", unit: "in")
            ResultRow(label: "IRC 2021 headroom", value: "6'-8\"")
            ResultRow(label: "IBC max riser / min tread", value: "7 / 11", unit: "in")
            note("IRC 2021 R311.7 · IBC 1011 — riser-to-riser variance ≤ 3/8\".")
        }.card()
    }

    private var rafterTable: some View {
        VStack(spacing: 8) {
            CardHeader(title: "Framing-square rafter table", trailing: "per ft run")
            HStack {
                Text("PITCH").font(.system(.caption2, design: .monospaced)).foregroundStyle(KC.textTertiary).frame(width: 64, alignment: .leading)
                Text("COMMON").font(.system(.caption2, design: .monospaced)).foregroundStyle(KC.textTertiary).frame(maxWidth: .infinity, alignment: .trailing)
                Text("HIP/VALLEY").font(.system(.caption2, design: .monospaced)).foregroundStyle(KC.textTertiary).frame(maxWidth: .infinity, alignment: .trailing)
            }
            ForEach(rafterRows, id: \.0) { row in
                HStack {
                    Text(row.0).font(.system(.callout, design: .monospaced).weight(.semibold)).foregroundStyle(KC.textPrimary).frame(width: 64, alignment: .leading)
                    Text(row.1).font(.system(.callout, design: .monospaced)).foregroundStyle(KC.textSecondary).frame(maxWidth: .infinity, alignment: .trailing)
                    Text(row.2).font(.system(.callout, design: .monospaced)).foregroundStyle(KC.textSecondary).frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            note("Matches the printed steel-square table (NAVEDTRA 14044).")
        }.card()
    }
    // In the app, compute from Rafter.commonPerFootRun / hipValleyPerFootRun as today.
    private let rafterRows = [("3/12", "12.37", "17.23"), ("4/12", "12.65", "17.44"),
                              ("6/12", "13.42", "18.00"), ("8/12", "14.42", "18.76"),
                              ("10/12", "15.62", "19.70"), ("12/12", "16.97", "20.78")]

    private var conversions: some View {
        VStack(spacing: 10) {
            CardHeader(title: "Exact conversions", trailing: "NIST SP 811")
            ResultRow(label: "1 inch", value: "25.4", unit: "mm")
            ResultRow(label: "1 foot", value: "0.3048", unit: "m")
            ResultRow(label: "1 yard", value: "0.9144", unit: "m")
            note("1959 international agreement. Survey foot deprecated 2023.")
        }.card()
    }

    private var bagYield: some View {
        VStack(spacing: 10) {
            CardHeader(title: "Concrete bag yield", trailing: "QUIKRETE #1101")
            ResultRow(label: "80 lb bag", value: "0.60", unit: "ft³")
            ResultRow(label: "60 lb bag", value: "0.45", unit: "ft³")
            ResultRow(label: "1 cubic yard", value: "45", unit: "× 80lb")
            note("27 ft³ per yd³.")
        }.card()
    }

    private var standards: some View {
        VStack(spacing: 8) {
            CardHeader(title: "Standards & editions", trailing: "validated against")
            ForEach(Standard.all) { s in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    (Text(s.name).foregroundStyle(KC.textPrimary)
                     + Text("  · \(s.governs)").foregroundStyle(KC.textTertiary))
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(s.edition)
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(KC.textSecondary)
                    Text(s.tier.rawValue.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(0.5)
                        .foregroundStyle(s.tierColor)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(s.tierColor.opacity(0.14), in: .rect(cornerRadius: 5))
                        .frame(width: 74, alignment: .trailing)
                }
            }
            note("Editions are what the on-device math is validated against. Codes revise on ~3-yr cycles and vary by jurisdiction — confirm against your adopted code.")
        }.card()
    }

    private var disclaimer: some View {
        Text("Kerf Calc is a field calculator, not certified engineering. Verify against your adopted local code before building. All math is offline and on-device.")
            .font(.footnote).foregroundStyle(KC.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
    }

    private func note(_ s: String) -> some View {
        Text(s).font(.caption).foregroundStyle(KC.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
