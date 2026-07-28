import SwiftUI
import FramingKit
import PipeKit

/// Reference tab — the cited constants the calculators are built on. Offline, always available.
struct ReferenceView: View {
    @EnvironmentObject private var router: Router
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var compactSection: ReferenceSection?

    /// Compact filters with the chip row; regular is driven by the Reference sidebar.
    private var activeSection: ReferenceSection? { hSize == .regular ? router.refSection : compactSection }
    private func shows(_ s: ReferenceSection) -> Bool { activeSection == nil || activeSection == s }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if hSize != .regular {
                        CategoryChips(items: CategoryChips<ReferenceSection>.referenceItems(), selection: $compactSection)
                    }
                    if hSize == .regular {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(spacing: 16) {
                                if shows(.codes) { stairCodes }
                                if shows(.conversions) { conversions }
                                if shows(.tables) { concrete }
                            }
                            VStack(spacing: 16) {
                                if shows(.tables) { rafterTable }
                                if shows(.tables) { fittingMultipliers }
                                if shows(.standards) { standards }
                            }.frame(maxWidth: .infinity)
                        }
                    } else {
                        if shows(.codes) { stairCodes }
                        if shows(.tables) { rafterTable }
                        if shows(.tables) { fittingMultipliers }
                        if shows(.conversions) { conversions }
                        if shows(.tables) { concrete }
                        if shows(.standards) { standards }
                    }
                    disclaimer
                }
                .frame(maxWidth: hSize == .regular ? 1100 : 640).frame(maxWidth: .infinity).padding(16)
            }
            .background(AppBackground())
            .navigationTitle("Reference")
        }
    }

    private var stairCodes: some View {
        VStack(spacing: 10) {
            CardHeader(title: "Stair code limits")
            ResultRow(label: "IRC 2021 max riser", value: "7 3/4", unit: "in")
            ResultRow(label: "IRC 2021 min tread", value: "10", unit: "in")
            ResultRow(label: "IRC 2021 headroom", value: "6'-8\"")
            ResultRow(label: "IBC max riser / min tread", value: "7 / 11", unit: "in")
            note("IRC 2021 R311.7 · IBC 1011 — riser-to-riser variance ≤ 3/8\".")
        }.card()
    }

    private var rafterTable: some View {
        VStack(spacing: 10) {
            CardHeader(title: "Framing-square rafter table", trailing: "per ft run")
            HStack {
                Text("Pitch").font(.caption.monospaced()).foregroundStyle(KC.textTertiary).frame(width: 60, alignment: .leading)
                Text("Common").font(.caption.monospaced()).foregroundStyle(KC.textTertiary).frame(maxWidth: .infinity, alignment: .trailing)
                Text("Hip/Valley").font(.caption.monospaced()).foregroundStyle(KC.textTertiary).frame(maxWidth: .infinity, alignment: .trailing)
            }
            ForEach([3, 4, 6, 8, 10, 12], id: \.self) { p in
                HStack {
                    Text("\(p)/12").font(.system(.callout, design: .monospaced)).foregroundStyle(KC.textPrimary).frame(width: 60, alignment: .leading)
                    Text(String(format: "%.2f", Rafter.commonPerFootRun(rise: Double(p)))).font(.system(.callout, design: .monospaced)).foregroundStyle(KC.textSecondary).frame(maxWidth: .infinity, alignment: .trailing)
                    Text(String(format: "%.2f", Rafter.hipValleyPerFootRun(rise: Double(p)))).font(.system(.callout, design: .monospaced)).foregroundStyle(KC.textSecondary).frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            note("Matches the printed steel-square table (NAVEDTRA 14044).")
        }.card()
    }

    /// The pipe trades' fitting multipliers. Not a transcribed table — every figure is computed live
    /// from `PipeKit`, which is exactly why the published constants and the trig agree.
    private var fittingMultipliers: some View {
        VStack(spacing: 8) {
            CardHeader(title: "Pipe fitting multipliers", trailing: "csc θ / cot θ")
            HStack {
                Text("FITTING").font(.system(.caption2, design: .monospaced)).foregroundStyle(KC.textTertiary).frame(width: 64, alignment: .leading)
                Text("TRAVEL").font(.system(.caption2, design: .monospaced)).foregroundStyle(KC.textTertiary).frame(maxWidth: .infinity, alignment: .trailing)
                Text("RUN").font(.system(.caption2, design: .monospaced)).foregroundStyle(KC.textTertiary).frame(maxWidth: .infinity, alignment: .trailing)
            }
            ForEach(fittingRows, id: \.0) { row in
                HStack {
                    Text(row.0).font(.system(.callout, design: .monospaced).weight(.semibold)).foregroundStyle(KC.textPrimary).frame(width: 64, alignment: .leading)
                    Text(String(format: "%.4f", PipeOffset.travelMultiplier(fittingAngleDeg: row.1)))
                        .font(.system(.callout, design: .monospaced)).foregroundStyle(KC.textSecondary).frame(maxWidth: .infinity, alignment: .trailing)
                    Text(String(format: "%.4f", PipeOffset.runMultiplier(fittingAngleDeg: row.1)))
                        .font(.system(.callout, design: .monospaced)).foregroundStyle(KC.textSecondary).frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            note("Travel = set × csc θ, run = set × cot θ. The trade's printed constants (45° → 1.414) are these identities.")
        }.card()
    }
    private let fittingRows: [(String, Double)] = [("60°", 60), ("45°", 45), ("30°", 30), ("22½°", 22.5), ("11¼°", 11.25)]

    private var conversions: some View {
        VStack(spacing: 10) {
            CardHeader(title: "Exact conversions (NIST)")
            ResultRow(label: "1 inch", value: "25.4", unit: "mm")
            ResultRow(label: "1 foot", value: "0.3048", unit: "m")
            ResultRow(label: "1 yard", value: "0.9144", unit: "m")
            note("NIST SP 811 — 1959 international agreement. International foot (survey foot deprecated 2023).")
        }.card()
    }

    private var concrete: some View {
        VStack(spacing: 10) {
            CardHeader(title: "Concrete bag yield")
            ResultRow(label: "80 lb bag", value: "0.60", unit: "ft³")
            ResultRow(label: "60 lb bag", value: "0.45", unit: "ft³")
            ResultRow(label: "1 cubic yard", value: "45", unit: "× 80lb")
            note("QUIKRETE #1101 data sheet · 27 ft³ per yd³.")
        }.card()
    }

    private var standards: some View {
        VStack(spacing: 10) {
            CardHeader(title: "Standards & editions", trailing: "validated against")
            ForEach(Standard.all) { s in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.name).font(.callout).foregroundStyle(KC.textPrimary)
                        Text(s.governs).font(.caption2).foregroundStyle(KC.textTertiary)
                    }
                    Spacer()
                    Text(s.edition)
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(KC.textSecondary)
                    Text(s.tier.rawValue.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(0.5)
                        .foregroundStyle(s.tierColor)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(s.tierColor.opacity(0.14), in: .rect(cornerRadius: 5))
                        .frame(width: 74, alignment: .trailing)
                }
            }
            note("Editions are what the on-device math is validated against. Codes revise on ~3-yr cycles and vary by jurisdiction — confirm against your adopted code. Product/market figures are editable in each tool.")
        }.card()
    }

    private var disclaimer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("kerfcalc is a field calculator, not certified engineering. Verify against your adopted local code before building. All math is offline and on-device.")
                .font(.footnote).foregroundStyle(KC.textTertiary)
        }.card()
    }

    private func note(_ s: String) -> some View {
        Text(s).font(.caption).foregroundStyle(KC.textTertiary).frame(maxWidth: .infinity, alignment: .leading)
    }
}
