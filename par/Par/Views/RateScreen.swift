import SwiftUI
import RateKit

/// The two regulated disclosures — Regulation Z's APR and Regulation DD's APY — plus the nominal ↔
/// effective conversion that sits underneath both.
public struct RateScreen: View {
    @StateObject private var model = RateViewModel()
    @Binding private var document: TapeDocument

    public init(document: Binding<TapeDocument>) {
        self._document = document
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SubScreenPicker(
                    options: RateViewModel.Mode.allCases.map { ($0, $0.rawValue) },
                    selection: $model.mode,
                    identifier: "rate.mode"
                )
                inputs
                hero
                secondary
                AppendToTapeBar(label: $model.rowLabel, canAppend: model.tapeRow() != nil,
                                identifier: "rate.tape") { append() }
                ProvenanceStrip(authorities: model.authorities, conventions: model.conventions,
                                identifier: "rate.provenance")
            }
            .padding(.horizontal, Par.Metrics.gutter)
            .padding(.bottom, 12)
        }
        .background(Par.Palette.base)
        .navigationTitle("Rate & APR")
    }

    @ViewBuilder
    private var inputs: some View {
        switch model.mode {
        case .apr:
            VStack(spacing: 0) {
                NumberField("A", caption: "amount advanced", unit: "USD",
                            value: $model.advance, range: RateViewModel.moneyRange, digits: 2,
                            identifier: "rate.input.advance")
                Divider().overlay(Par.Palette.separator)
                NumberField("P", caption: "payment", unit: "USD",
                            value: $model.payment, range: RateViewModel.moneyRange, digits: 2,
                            identifier: "rate.input.payment")
                Divider().overlay(Par.Palette.separator)
                NumberField("n", caption: "number of payments", unit: "count",
                            value: $model.paymentCount, range: RateViewModel.countRange, digits: 0,
                            identifier: "rate.input.paymentCount")
                Divider().overlay(Par.Palette.separator)
                NumberField("w", caption: "unit-periods per year", unit: "count",
                            value: $model.unitPeriodsPerYear, range: RateViewModel.frequencyRange,
                            digits: 0, identifier: "rate.input.unitPeriodsPerYear")
            }
            .glassCard()
        case .apy:
            VStack(spacing: 0) {
                NumberField("INT", caption: "interest earned", unit: "USD",
                            value: $model.interest, range: RateViewModel.interestRange, digits: 2,
                            identifier: "rate.input.interest")
                Divider().overlay(Par.Palette.separator)
                NumberField("BAL", caption: "principal", unit: "USD",
                            value: $model.principal, range: RateViewModel.moneyRange, digits: 2,
                            identifier: "rate.input.principal")
                Divider().overlay(Par.Palette.separator)
                NumberField("d", caption: "days in term", unit: "days",
                            value: $model.daysInTerm, range: RateViewModel.daysRange, digits: 0,
                            identifier: "rate.input.daysInTerm")
            }
            .glassCard()
        case .convert:
            VStack(spacing: 0) {
                NumberField("NOM", caption: "nominal annual rate", unit: "%",
                            value: $model.nominalPct, range: RateViewModel.ratePctRange, digits: 4,
                            identifier: "rate.input.nominal")
                Divider().overlay(Par.Palette.separator)
                NumberField("m", caption: "compounds per year", unit: "count",
                            value: $model.timesPerYear, range: RateViewModel.frequencyRange,
                            digits: 0, identifier: "rate.input.timesPerYear")
            }
            .glassCard()
        }
    }

    @ViewBuilder
    private var hero: some View {
        switch model.outcome {
        case .solved(let value):
            HeroResult(caption: model.heroCaption,
                       value: Fmt.percent(value),
                       footnote: model.heroFootnote,
                       identifier: "rate.hero",
                       spoken: Fmt.spokenPercent(value, label: model.heroCaption))
        case .failed(let message):
            FailureNotice(
                title: "These payments never balance the advance",
                detail: message,
                technical: "Rate.RateError · nothing was appended to the tape",
                identifier: "rate.hero.failure"
            )
        }
    }

    @ViewBuilder
    private var secondary: some View {
        switch model.mode {
        case .apr:
            VStack(spacing: 0) {
                ResultRow("total of payments", value: Fmt.money(model.totalOfPayments), unit: "USD",
                          identifier: "rate.totalOfPayments",
                          spoken: Fmt.spokenMoney(model.totalOfPayments, label: "total of payments"))
                Divider().overlay(Par.Palette.separator)
                ResultRow("finance charge", value: Fmt.money(model.financeCharge), unit: "USD",
                          emphasis: .strong, identifier: "rate.financeCharge",
                          spoken: Fmt.spokenMoney(model.financeCharge, label: "finance charge"))
            }
            .glassCard()
        case .apy:
            EmptyView()
        case .convert:
            VStack(spacing: 0) {
                ResultRow("continuous", value: Fmt.percent(model.continuousEquivalent),
                          identifier: "rate.continuous",
                          spoken: Fmt.spokenPercent(model.continuousEquivalent,
                                                    label: "continuously compounded equivalent"))
                Divider().overlay(Par.Palette.separator)
                ResultRow("nominal, if i% were effective",
                          value: Fmt.percent(model.nominalIfRateWereEffective),
                          identifier: "rate.nominalIfRateWereEffective",
                          spoken: Fmt.spokenPercent(model.nominalIfRateWereEffective,
                                                    label: "nominal rate, if the entered rate were effective"))
            }
            .glassCard()
        }
    }

    private func append() {
        if let row = model.tapeRow() { document.append(row) }
    }
}

#Preview("Rate — dark") {
    NavigationStack { RateScreen(document: .constant(TapeDocument())) }.parAppearance()
}

#Preview("Rate — AX5") {
    NavigationStack { RateScreen(document: .constant(TapeDocument())) }
        .environment(\.dynamicTypeSize, .accessibility5)
        .parAppearance()
}
