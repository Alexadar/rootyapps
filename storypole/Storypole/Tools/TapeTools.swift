import SwiftUI
import DimensionKit

// MARK: - Convert

struct ConvertToolView: View {
    @State private var text = "12' 6-1/2\""
    @State private var denominator: Int64 = 16
    @State private var useSurveyFoot = false

    private var value: FeetInch? { FeetInch.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: SP.s3) {
            DimensionField(label: "Measurement", text: $text, identifier: "convert.input")
            DenominatorPicker(denominator: $denominator)

            if let v = value {
                VStack(spacing: SP.s3) {
                    ResultRow(label: "Feet & inches", value: v.formatted(toDenominator: denominator),
                              emphasis: true, identifier: "convert.feetInch")
                    ResultRow(label: "Inches (decimal)", value: Fmt.f(v.inchesValue, 4), unit: "in",
                              identifier: "convert.inches")
                    ResultRow(label: "Feet (decimal)", value: Fmt.f(v.feetValue, 4), unit: "ft",
                              identifier: "convert.feet")
                    ResultRow(label: "Millimetres",
                              value: Fmt.f(Units.convert(v.inchesValue, from: .inch, to: .millimeter), 2),
                              unit: "mm", identifier: "convert.mm")
                    ResultRow(label: "Metres",
                              value: Fmt.f(Units.convert(v.inchesValue, from: .inch, to: .meter), 4),
                              unit: "m", identifier: "convert.m")
                }
                .spCard()

                Toggle("US survey foot (legacy)", isOn: $useSurveyFoot)
                    .font(SPType.label)
                    .accessibilityIdentifier("convert.surveyFoot")
                if useSurveyFoot {
                    let metres = v.feetValue * Units.surveyFootMeters.doubleValue
                    VStack(alignment: .leading, spacing: SP.s2) {
                        ResultRow(label: "Metres (survey foot)", value: Fmt.f(metres, 4), unit: "m",
                                  identifier: "convert.surveyMetres")
                        Text("Deprecated. \"Beginning on January 1, 2023, the U.S. survey foot should not be used.\" — 85 FR 62698")
                            .font(SPType.footnote).foregroundStyle(SP.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .spCard()
                }
            }
        }
    }
}

// MARK: - Fraction rounding

struct FractionToolView: View {
    @State private var text = "8-7/16\""
    @State private var denominator: Int64 = 16
    @State private var rule: RoundingRule = .halfToEven

    private var value: FeetInch? { FeetInch.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: SP.s3) {
            DimensionField(label: "Measurement", text: $text, identifier: "fraction.input")
            DenominatorPicker(denominator: $denominator)

            Picker("Ties", selection: $rule) {
                Text("To even (NIST)").tag(RoundingRule.halfToEven)
                Text("Away from zero").tag(RoundingRule.halfAwayFromZero)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("fraction.rule")

            if let v = value {
                VStack(spacing: SP.s3) {
                    ResultRow(label: "Rounded", value: v.formatted(toDenominator: denominator, rule: rule),
                              emphasis: true, identifier: "fraction.result")
                    ResultRow(label: "Exact", value: v.inches.description, unit: "in",
                              identifier: "fraction.exact")
                    let other: RoundingRule = rule == .halfToEven ? .halfAwayFromZero : .halfToEven
                    let otherText = v.formatted(toDenominator: denominator, rule: other)
                    if otherText != v.formatted(toDenominator: denominator, rule: rule) {
                        ResultRow(label: "Other rule would give", value: otherText,
                                  identifier: "fraction.other")
                    }
                }
                .spCard()
            }

            Text("""
                 Ties go to the even neighbour by default, per NIST SP 811 §B.7.1. The lumber \
                 standard proves it: a dressed 7-1/2\" is 190.5 mm exactly, and PS 20-20 Table 3 \
                 publishes 190 mm, not 191.
                 """)
                .font(SPType.footnote).foregroundStyle(SP.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview("Convert")  { ScrollView { ConvertToolView().padding() }.background(SP.background) }
#Preview("Fraction") { ScrollView { FractionToolView().padding() }.background(SP.background) }
