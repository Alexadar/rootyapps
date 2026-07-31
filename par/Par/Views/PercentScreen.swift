import SwiftUI
import PercentKit

/// Markup versus margin, and break-even. Both answers are shown at once, because confusing the two
/// is the expensive mistake this screen exists to prevent.
public struct PercentScreen: View {
    @StateObject private var model = PercentViewModel()
    @Binding private var document: TapeDocument

    public init(document: Binding<TapeDocument>) {
        self._document = document
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SubScreenPicker(
                    options: PercentViewModel.Mode.allCases.map { ($0, $0.rawValue) },
                    selection: $model.mode,
                    identifier: "percent.mode"
                )
                inputs
                hero
                secondary
                AppendToTapeBar(label: $model.rowLabel, canAppend: model.tapeRow() != nil,
                                identifier: "percent.tape") { append() }
                ProvenanceStrip(authorities: model.authorities, conventions: model.conventions,
                                identifier: "percent.provenance")
            }
            .padding(.horizontal, Par.Metrics.gutter)
            .padding(.bottom, 12)
        }
        .background(Par.Palette.base)
        .navigationTitle("Percent & Margin")
    }

    @ViewBuilder
    private var inputs: some View {
        switch model.mode {
        case .margin:
            VStack(spacing: 0) {
                NumberField("CST", caption: "cost", unit: "USD",
                            value: $model.cost, range: PercentViewModel.moneyRange, digits: 2,
                            identifier: "percent.input.cost")
                Divider().overlay(Par.Palette.separator)
                NumberField("SEL", caption: "selling price", unit: "USD",
                            value: $model.price, range: PercentViewModel.moneyRange, digits: 2,
                            identifier: "percent.input.price")
            }
            .glassCard()
        case .change:
            // The two values are stored in the same scalars the margin mode uses, so a change row
            // costs the file format nothing. Only the labels differ.
            VStack(spacing: 0) {
                NumberField("FRM", caption: "from", unit: "value",
                            value: $model.cost, range: -1_000_000_000...1_000_000_000, digits: 2,
                            identifier: "percent.input.from")
                Divider().overlay(Par.Palette.separator)
                NumberField("TO", caption: "to", unit: "value",
                            value: $model.price, range: -1_000_000_000...1_000_000_000, digits: 2,
                            identifier: "percent.input.to")
            }
            .glassCard()
        case .breakEven:
            VStack(spacing: 0) {
                NumberField("FIX", caption: "fixed costs", unit: "USD",
                            value: $model.fixedCosts, range: PercentViewModel.fixedRange, digits: 2,
                            identifier: "percent.input.fixedCosts")
                Divider().overlay(Par.Palette.separator)
                NumberField("SEL", caption: "price per unit", unit: "USD",
                            value: $model.price, range: PercentViewModel.moneyRange, digits: 2,
                            identifier: "percent.input.pricePerUnit")
                Divider().overlay(Par.Palette.separator)
                NumberField("VAR", caption: "variable cost per unit", unit: "USD",
                            value: $model.variableCostPerUnit, range: PercentViewModel.fixedRange,
                            digits: 2, identifier: "percent.input.variableCost")
                Divider().overlay(Par.Palette.separator)
                NumberField("TGT", caption: "target profit", unit: "USD",
                            value: $model.targetProfit, range: PercentViewModel.profitRange,
                            digits: 2, identifier: "percent.input.targetProfit")
            }
            .glassCard()
        }
    }

    @ViewBuilder
    private var hero: some View {
        switch model.outcome {
        case .solved(let value):
            HeroResult(
                caption: model.heroCaption,
                value: model.mode == .breakEven
                    ? Fmt.count(value) : Fmt.percent(value, digits: 2),
                footnote: model.heroFootnote,
                identifier: "percent.hero",
                spoken: model.mode == .breakEven
                    ? "\(Fmt.count(value)) units to break even"
                    : Fmt.spokenPercent(value, label: model.mode == .margin
                                        ? "gross margin" : "percent change", digits: 2)
            )
        case .failed(let message):
            FailureNotice(
                title: model.mode == .change ? "No change to report" : "No volume breaks even",
                detail: message,
                technical: "contribution margin ≤ 0 · nothing was appended to the tape",
                identifier: "percent.hero.failure"
            )
        }
    }

    @ViewBuilder
    private var secondary: some View {
        switch model.mode {
        case .margin:
            VStack(spacing: 0) {
                // Both numbers, always, side by side. A 50% markup is a 33⅓% margin.
                ResultRow("markup on cost", value: Fmt.percent(model.markup, digits: 2),
                          emphasis: .strong, identifier: "percent.markup",
                          spoken: Fmt.spokenPercent(model.markup, label: "markup on cost", digits: 2))
                Divider().overlay(Par.Palette.separator)
                ResultRow("margin on price", value: Fmt.percent(model.margin, digits: 2),
                          identifier: "percent.margin",
                          spoken: Fmt.spokenPercent(model.margin, label: "margin on price", digits: 2))
                Divider().overlay(Par.Palette.separator)
                ResultRow("gross profit", value: Fmt.money(model.grossProfit), unit: "USD",
                          identifier: "percent.grossProfit",
                          spoken: Fmt.spokenMoney(model.grossProfit, label: "gross profit"))
            }
            .glassCard()
        case .change:
            // Results, not a second copy of the inputs. This branch previously repeated the FRM/TO
            // fields from `inputs` verbatim — same bindings, same identifiers — so the screen showed
            // the pair twice and `percent.input.from` matched two elements.
            VStack(spacing: 0) {
                ResultRow("absolute change", value: Fmt.money(model.absoluteChange), unit: "value",
                          emphasis: .strong, identifier: "percent.absoluteChange",
                          spoken: Fmt.spokenMoney(model.absoluteChange, label: "absolute change",
                                                  currency: "units"))
                Divider().overlay(Par.Palette.separator)
                // The question anyone asks next: if it moves again by the same percentage, where
                // does it land? A fall and the rise back are not equal, and this row is where that
                // becomes visible rather than assumed.
                ResultRow("again at the same rate", value: Fmt.money(model.compoundedOnce),
                          unit: "value", identifier: "percent.compoundedOnce",
                          spoken: Fmt.spokenMoney(model.compoundedOnce,
                                                  label: "the same change applied again",
                                                  currency: "units"))
            }
            .glassCard()
        case .breakEven:
            VStack(spacing: 0) {
                ResultRow("contribution per unit", value: Fmt.money(model.contributionMargin),
                          unit: "USD", emphasis: .strong, identifier: "percent.contribution",
                          spoken: Fmt.spokenMoney(model.contributionMargin,
                                                  label: "contribution per unit"))
                Divider().overlay(Par.Palette.separator)
                ResultRow("contribution margin", value: Fmt.percent(model.contributionMarginPct, digits: 2),
                          identifier: "percent.contributionPct",
                          spoken: Fmt.spokenPercent(model.contributionMarginPct,
                                                    label: "contribution margin", digits: 2))
                Divider().overlay(Par.Palette.separator)
                ResultRow("revenue at break-even", value: Fmt.money(model.breakEvenRevenue),
                          unit: "USD", identifier: "percent.breakEvenRevenue",
                          spoken: Fmt.spokenMoney(model.breakEvenRevenue, label: "revenue at break-even"))
            }
            .glassCard()
        }
    }

    private func append() {
        if let row = model.tapeRow() { document.append(row) }
    }
}

#Preview("Percent — dark") {
    NavigationStack { PercentScreen(document: .constant(TapeDocument())) }.parAppearance()
}

#Preview("Percent — AX5") {
    NavigationStack { PercentScreen(document: .constant(TapeDocument())) }
        .environment(\.dynamicTypeSize, .accessibility5)
        .parAppearance()
}
