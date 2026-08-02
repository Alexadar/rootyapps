import SwiftUI
import RealEstateKit

/// Income-property underwriting: rent roll → NOI → value, then the two tests a lender applies. The
/// screen's job is to say *which* test binds, because that is what a borrower negotiates against.
public struct RealEstateScreen: View {
    @StateObject private var model = RealEstateViewModel()
    @Binding private var document: TapeDocument

    public init(document: Binding<TapeDocument>) {
        self._document = document
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                rentRoll
                income
                hero
                loanTerms
                sizing
                returns
                AppendToTapeBar(label: $model.rowLabel, canAppend: model.tapeRow() != nil,
                                identifier: "realestate.tape") { append() }
                ProvenanceStrip(authorities: model.authorities, conventions: model.conventions,
                                identifier: "realestate.provenance")
            }
            .padding(.horizontal, Par.Metrics.gutter)
            .padding(.bottom, 12)
        }
        .background(Par.Palette.base)
        .navigationTitle("Real Estate")
    }

    private var rentRoll: some View {
        VStack(spacing: 0) {
            NumberField("GPR", caption: "gross potential rent", unit: "USD / yr",
                        value: $model.grossPotentialRent, range: RealEstateViewModel.moneyRange,
                        digits: 0, identifier: "realestate.input.gpr")
            Divider().overlay(Par.Palette.separator)
            NumberField("VAC", caption: "vacancy", unit: "%",
                        value: $model.vacancyPct, range: RealEstateViewModel.vacancyRange,
                        digits: 2, identifier: "realestate.input.vacancy")
            Divider().overlay(Par.Palette.separator)
            NumberField("OTH", caption: "other income", unit: "USD / yr",
                        value: $model.otherIncome, range: RealEstateViewModel.moneyRange,
                        digits: 0, identifier: "realestate.input.otherIncome")
            Divider().overlay(Par.Palette.separator)
            NumberField("OPX", caption: "operating expenses", unit: "USD / yr",
                        value: $model.operatingExpenses, range: RealEstateViewModel.moneyRange,
                        digits: 0, identifier: "realestate.input.operatingExpenses")
            Divider().overlay(Par.Palette.separator)
            NumberField("RSV", caption: "reserves", unit: "USD / yr",
                        value: $model.reserves, range: RealEstateViewModel.moneyRange,
                        digits: 0, identifier: "realestate.input.reserves")
            Divider().overlay(Par.Palette.separator)
            NumberField("VAL", caption: "value or price", unit: "USD",
                        value: $model.value, range: RealEstateViewModel.valueRange,
                        digits: 0, identifier: "realestate.input.value")
        }
        .glassCard()
    }

    private var income: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { incomeCards }
            VStack(spacing: 8) { incomeCards }
        }
    }

    @ViewBuilder
    private var incomeCards: some View {
        ResultRow("EGI", value: Fmt.money(model.effectiveGrossIncome, digits: 0), unit: "USD",
                  identifier: "realestate.egi",
                  spoken: Fmt.spokenMoney(model.effectiveGrossIncome, label: "effective gross income"))
        ResultRow("NOI", value: Fmt.money(model.netOperatingIncome, digits: 0), unit: "USD",
                  emphasis: .strong, identifier: "realestate.noi",
                  spoken: Fmt.spokenMoney(model.netOperatingIncome, label: "net operating income"))
        ResultRow("cap rate", value: Fmt.percent(model.capRate * 100, digits: 2),
                  identifier: "realestate.capRate",
                  spoken: Fmt.spokenPercent(model.capRate * 100, label: "capitalisation rate", digits: 2))
    }

    @ViewBuilder
    private var hero: some View {
        switch model.outcome {
        case .sized(let sizing):
            HeroResult(
                caption: "maximum loan · \(model.bindingTest)",
                value: Fmt.money(sizing.loan, digits: 0),
                footnote: "coverage \(Fmt.money(sizing.byDSCR, digits: 0)) · "
                    + "LTV \(Fmt.money(sizing.byLTV, digits: 0))",
                identifier: "realestate.hero",
                spoken: Fmt.spokenMoney(sizing.loan, label: "maximum loan")
            )
        case .failed(let message):
            FailureNotice(
                title: "This property supports no loan",
                detail: message,
                technical: "NOI ≤ 0 · nothing was appended to the tape",
                identifier: "realestate.hero.failure"
            )
        }
    }

    private var loanTerms: some View {
        VStack(spacing: 0) {
            NumberField("DSCR", caption: "target coverage", unit: "×",
                        value: $model.targetDSCR, range: RealEstateViewModel.dscrRange,
                        digits: 2, identifier: "realestate.input.dscr")
            Divider().overlay(Par.Palette.separator)
            NumberField("LTV", caption: "maximum loan to value", unit: "%",
                        value: $model.maxLTVPct, range: RealEstateViewModel.ltvRange,
                        digits: 1, identifier: "realestate.input.ltv")
            Divider().overlay(Par.Palette.separator)
            NumberField("i%", caption: "annual rate", unit: "nominal",
                        value: $model.annualRatePct, range: RealEstateViewModel.ratePctRange,
                        digits: 3, identifier: "realestate.input.rate")
            Divider().overlay(Par.Palette.separator)
            NumberField("AM", caption: "amortization", unit: "years",
                        value: $model.amortizationYears, range: RealEstateViewModel.amortRange,
                        digits: 0, identifier: "realestate.input.amortization")
        }
        .glassCard()
    }

    @ViewBuilder
    private var sizing: some View {
        if case .sized(let loanSizing) = model.outcome {
            VStack(spacing: 0) {
                ResultRow("by coverage", value: Fmt.money(loanSizing.byDSCR, digits: 0), unit: "USD",
                          emphasis: loanSizing.dscrConstrained ? .strong : .normal,
                          identifier: "realestate.byDSCR",
                          spoken: Fmt.spokenMoney(loanSizing.byDSCR, label: "loan by coverage"))
                Divider().overlay(Par.Palette.separator)
                ResultRow("by loan to value", value: Fmt.money(loanSizing.byLTV, digits: 0), unit: "USD",
                          emphasis: loanSizing.dscrConstrained ? .normal : .strong,
                          identifier: "realestate.byLTV",
                          spoken: Fmt.spokenMoney(loanSizing.byLTV, label: "loan by loan to value"))
                Divider().overlay(Par.Palette.separator)
                ResultRow("annual debt service", value: Fmt.money(model.annualDebtService, digits: 0),
                          unit: "USD", identifier: "realestate.debtService",
                          spoken: Fmt.spokenMoney(model.annualDebtService, label: "annual debt service"))
                Divider().overlay(Par.Palette.separator)
                ResultRow("mortgage constant", value: Fmt.percent(model.mortgageConstant * 100, digits: 3),
                          identifier: "realestate.constant",
                          spoken: Fmt.spokenPercent(model.mortgageConstant * 100,
                                                    label: "mortgage constant"))
            }
            .glassCard()
        }
    }

    private var returns: some View {
        VStack(spacing: 0) {
            ResultRow("cash flow before tax", value: Fmt.money(model.cashFlowBeforeTax, digits: 0),
                      unit: "USD", identifier: "realestate.cashFlow",
                      spoken: Fmt.spokenMoney(model.cashFlowBeforeTax, label: "cash flow before tax"))
            Divider().overlay(Par.Palette.separator)
            ResultRow("cash on cash", value: Fmt.percent(model.cashOnCash, digits: 2),
                      emphasis: .strong, identifier: "realestate.cashOnCash",
                      spoken: Fmt.spokenPercent(model.cashOnCash, label: "cash on cash return", digits: 2))
            Divider().overlay(Par.Palette.separator)
            ResultRow("break-even occupancy", value: Fmt.percent(model.breakEvenOccupancy, digits: 1),
                      identifier: "realestate.breakEven",
                      spoken: Fmt.spokenPercent(model.breakEvenOccupancy,
                                                label: "break-even occupancy", digits: 1))
            Divider().overlay(Par.Palette.separator)
            // The sentence that decides a deal: leverage only helps above the mortgage constant.
            ResultRow("leverage", value: model.leverageIsAccretive ? "accretive" : "dilutive",
                      identifier: "realestate.leverage",
                      spoken: model.leverageIsAccretive
                          ? "leverage raises the return: the cap rate exceeds the mortgage constant"
                          : "leverage lowers the return: the mortgage constant exceeds the cap rate")
        }
        .glassCard()
    }

    private func append() {
        if let row = model.tapeRow() { document.append(row) }
    }
}

#Preview("Real Estate — dark") {
    NavigationStack { RealEstateScreen(document: .constant(TapeDocument())) }.parAppearance()
}

#Preview("Real Estate — AX5") {
    NavigationStack { RealEstateScreen(document: .constant(TapeDocument())) }
        .environment(\.dynamicTypeSize, .accessibility5)
        .parAppearance()
}
