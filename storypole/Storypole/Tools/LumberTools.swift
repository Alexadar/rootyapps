import SwiftUI
import DimensionKit
import LumberKit
import GaugeKit

// MARK: - Board feet

struct BoardFeetToolView: View {
    @State private var thickness = 2.0
    @State private var width = 4.0
    @State private var lengthFt = 8.0
    @State private var pieces = 1

    var body: some View {
        VStack(alignment: .leading, spacing: SP.s3) {
            NumberField(label: "Nominal thickness", value: $thickness, unit: "in", range: 0.25...24,
                        identifier: "bf.thickness")
            NumberField(label: "Nominal width", value: $width, unit: "in", range: 0.25...48,
                        identifier: "bf.width")
            NumberField(label: "Length", value: $lengthFt, unit: "ft", range: 0.25...100,
                        identifier: "bf.length")
            Stepper("Pieces: \(pieces)", value: $pieces, in: 1...999)
                .font(SPType.label).accessibilityIdentifier("bf.pieces")

            let one = BoardFeet.value(thicknessIn: thickness, widthIn: width, lengthFt: lengthFt)
            VStack(spacing: SP.s3) {
                ResultRow(label: "Board feet (total)", value: Fmt.f(one * Double(pieces), 3),
                          unit: "BF", emphasis: true, identifier: "bf.total")
                ResultRow(label: "Each piece", value: Fmt.f(one, 4), unit: "BF", identifier: "bf.each")
            }
            .spCard()

            VStack(alignment: .leading, spacing: SP.s2) {
                Text("Nominal, not dressed")
                    .font(SPType.eyebrow).foregroundStyle(SP.textSecondary)
                Text(BoardFeet.cubicMetreCaution)
                    .font(SPType.footnote).foregroundStyle(SP.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .spCard()
            .spProse("bf.caution")
        }
    }
}

// MARK: - Nominal vs dressed

struct DressedSizeToolView: View {
    @State private var seasoning: DressedSize.Seasoning = .dry

    var body: some View {
        VStack(alignment: .leading, spacing: SP.s3) {
            Picker("Seasoning", selection: $seasoning) {
                Text("Dry").tag(DressedSize.Seasoning.dry)
                Text("Green").tag(DressedSize.Seasoning.green)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("dressed.seasoning")

            VStack(spacing: 0) {
                HStack {
                    Text("Nominal").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Dressed").frame(maxWidth: .infinity, alignment: .leading)
                    Text("mm").frame(width: 44, alignment: .trailing)
                }
                .font(SPType.eyebrow)
                .foregroundStyle(SP.textSecondary)
                .padding(.bottom, 6)

                ForEach(Array(DressedSize.table.enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(FeetInch(inches: row.nominalIn).formatted(toDenominator: 32))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(FeetInch(inches: row.dressed(seasoning)).formatted(toDenominator: 32))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(seasoning == .dry ? String(row.dryMM) : "—")
                            .frame(width: 44, alignment: .trailing)
                            .foregroundStyle(SP.textTertiary)
                    }
                    .font(SPType.mark)
                    .padding(.vertical, 3)
                }
            }
            .spCard()
            .accessibilityIdentifier("dressed.table")

            VStack(alignment: .leading, spacing: SP.s2) {
                Text("A 2×4 is 1-1/2\" × 3-1/2\" dry — 65.6 % of the section you are billed for.")
                    .font(SPType.label).foregroundStyle(SP.textSecondary)
                Text(DressedSize.nominalDisclaimer)
                    .font(SPType.footnote).foregroundStyle(SP.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .spCard()
        }
    }
}

// MARK: - Wire gauge

struct WireGaugeToolView: View {
    @State private var gage = 12

    var body: some View {
        VStack(alignment: .leading, spacing: SP.s3) {
            Stepper("Gage: \(AWG.name(gage: gage))", value: $gage, in: -3...36)
                .font(SPType.label)
                .accessibilityIdentifier("awg.gage")

            VStack(spacing: SP.s3) {
                ResultRow(label: "Diameter", value: Fmt.f(AWG.diameterInch(gage: gage), 4), unit: "in",
                          emphasis: true, identifier: "awg.inch")
                ResultRow(label: "Diameter", value: Fmt.f(AWG.diameterMillimetres(gage: gage), 3), unit: "mm",
                          identifier: "awg.mm")
                ResultRow(label: "Area", value: Fmt.f(AWG.areaCircularMils(gage: gage), 1), unit: "cmil",
                          identifier: "awg.cmil")
            }
            .spCard()

            VStack(alignment: .leading, spacing: SP.s2) {
                Text("Dimension only")
                    .font(SPType.eyebrow).foregroundStyle(SP.accent)
                Text("""
                     No. 0000 is defined as 0.4600 inch and No. 36 as 0.0050 inch, with 38 sizes \
                     between, so each step is the 39th root of 92 — 1.1229322 (NBS Handbook 100 §2.1).

                     Ampacity, conductor sizing, voltage drop and box fill are code questions with \
                     safety consequences. Storypole does not answer them.
                     """)
                    .font(SPType.footnote).foregroundStyle(SP.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .spCard()
            .spProse("awg.caveat")
        }
    }
}

#Preview("Board feet")   { ScrollView { BoardFeetToolView().padding() }.background(SP.background) }
#Preview("Dressed size") { ScrollView { DressedSizeToolView().padding() }.background(SP.background) }
#Preview("Wire gauge")   { ScrollView { WireGaugeToolView().padding() }.background(SP.background) }
