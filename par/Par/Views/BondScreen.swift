import SwiftUI
import BondKit
import DayCountKit

/// Price and yield, with the settlement day counts visible — because a bond price without its
/// convention is a number without a meaning.
public struct BondScreen: View {
    @StateObject private var model = BondViewModel()
    @Binding private var document: TapeDocument

    public init(document: Binding<TapeDocument>) {
        self._document = document
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                direction
                inputs
                firstPeriodCard
                hero
                riskMeasures
                AppendToTapeBar(label: $model.rowLabel, canAppend: model.tapeRow() != nil,
                                identifier: "bond.tape") { append() }
                ProvenanceStrip(authorities: model.authorities, conventions: model.conventions,
                                identifier: "bond.provenance")
            }
            .padding(.horizontal, Par.Metrics.gutter)
            .padding(.bottom, 12)
        }
        .background(Par.Palette.base)
        .navigationTitle("Bond")
    }

    /// Appendix B states five price formulas and the first-period case is what selects among them.
    /// The Kit has always implemented all five; until now the screen could only ever reach §II.A, so
    /// a stub period — ordinary in a new issue — was unpriceable.
    private var firstPeriodCard: some View {
        SettingCard("first period", value: model.firstPeriod.shortName,
                    identifier: "bond.firstPeriod",
                    spoken: "first interest payment period, \(model.firstPeriod.shortName)") {
            Picker("first period", selection: $model.firstPeriod) {
                ForEach(Bond.FirstPeriod.allCases, id: \.self) { period in
                    Text(BondViewModel.sectionName(period)).tag(period)
                }
            }
            .pickerStyle(.inline)
        }
    }

    /// Which direction the screen solves. Both were always computable; only one was reachable.
    private var direction: some View {
        SubScreenPicker(
            options: BondViewModel.SolveFor.allCases.map { ($0, $0.rawValue) },
            selection: $model.solveFor,
            identifier: "bond.solveFor"
        )
    }

    private var inputs: some View {
        VStack(spacing: 0) {
            if model.solveFor == .yield {
                NumberField("PRC", caption: "price", unit: "per 100",
                            value: $model.price, range: BondViewModel.priceRange, digits: 3,
                            identifier: "bond.input.price")
            } else {
                NumberField("YLD", caption: "yield to maturity", unit: "nominal",
                            value: $model.yieldPct, range: BondViewModel.yieldRange, digits: 3,
                            identifier: "bond.input.yield")
            }
            Divider().overlay(Par.Palette.separator)
            NumberField("CPN", caption: "annual coupon", unit: "per 100",
                        value: $model.couponPct, range: BondViewModel.couponRange, digits: 3,
                        identifier: "bond.input.coupon")
            Divider().overlay(Par.Palette.separator)
            NumberField("n", caption: "full semiannual periods", unit: "count",
                        value: intBinding(\.fullPeriods), range: 0...120, digits: 0,
                        identifier: "bond.input.fullPeriods")
            Divider().overlay(Par.Palette.separator)
            NumberField("r", caption: "days to next coupon", unit: "days",
                        value: intBinding(\.daysToNextCoupon), range: 0...400, digits: 0,
                        identifier: "bond.input.daysToNextCoupon")
            Divider().overlay(Par.Palette.separator)
            // s must be > 0: the Kit's precondition, made un-enterable rather than trapped.
            NumberField("s", caption: "days in the coupon period", unit: "days",
                        value: intBinding(\.daysInPeriod), range: 1...400, digits: 0,
                        identifier: "bond.input.daysInPeriod")
        }
        .glassCard()
    }

    private func intBinding(_ keyPath: ReferenceWritableKeyPath<BondViewModel, Int>) -> Binding<Double> {
        Binding(get: { Double(model[keyPath: keyPath]) },
                set: { model[keyPath: keyPath] = Int($0) })
    }

    @ViewBuilder
    private var hero: some View {
        switch model.yieldToMaturity {
        case .solved(let yield):
            // The hero is whichever number was solved for, not always the yield.
            if model.solveFor == .price {
                HeroResult(caption: "PRC · price per 100 of par",
                           value: Fmt.price(model.effectivePrice, digits: 6),
                           footnote: "at \(Fmt.percent(yield * 100)) nominal, semiannual",
                           identifier: "bond.hero",
                           spoken: "price \(Fmt.price(model.effectivePrice, digits: 4)) per 100")
            } else {
                HeroResult(caption: "YTM · yield to maturity",
                           value: Fmt.percent(yield * 100),
                           footnote: "nominal, semiannual · price \(Fmt.price(model.price, digits: 3))",
                           identifier: "bond.hero",
                           spoken: Fmt.spokenPercent(yield * 100, label: "yield to maturity"))
            }
        case .failed(let message):
            FailureNotice(
                title: "No yield produces that price",
                detail: message,
                technical: "Bond.YieldError.priceOutOfRange · nothing was appended to the tape",
                identifier: "bond.hero.failure"
            )
        }
    }

    private var riskMeasures: some View {
        VStack(spacing: 0) {
            ResultRow("accrued interest", value: Fmt.price(model.accruedInterest, digits: 6),
                      unit: "per 100", identifier: "bond.accrued",
                      spoken: "accrued interest \(Fmt.price(model.accruedInterest, digits: 4)) per 100")
            Divider().overlay(Par.Palette.separator)
            ResultRow("invoice price", value: Fmt.price(model.invoicePrice, digits: 6),
                      unit: "per 100", emphasis: .strong, identifier: "bond.invoice",
                      spoken: "invoice price \(Fmt.price(model.invoicePrice, digits: 4)) per 100")
            Divider().overlay(Par.Palette.separator)
            ResultRow("current yield", value: Fmt.percent(model.currentYieldPct),
                      identifier: "bond.currentYield",
                      spoken: Fmt.spokenPercent(model.currentYieldPct, label: "current yield"))
            if case .solved(let yield) = model.yieldToMaturity {
                Divider().overlay(Par.Palette.separator)
                ResultRow("Macaulay duration", value: Fmt.count(model.macaulayDuration(at: yield)),
                          unit: "years", identifier: "bond.macaulay",
                          spoken: "Macaulay duration \(Fmt.count(model.macaulayDuration(at: yield))) years")
                Divider().overlay(Par.Palette.separator)
                ResultRow("modified duration", value: Fmt.count(model.modifiedDuration(at: yield)),
                          unit: "years", identifier: "bond.modified",
                          spoken: "modified duration \(Fmt.count(model.modifiedDuration(at: yield))) years")
                Divider().overlay(Par.Palette.separator)
                ResultRow("convexity", value: Fmt.count(model.convexity(at: yield)),
                          unit: "years²", identifier: "bond.convexity",
                          spoken: "convexity \(Fmt.count(model.convexity(at: yield)))")
            }
        }
        .glassCard()
    }

    private func append() {
        if let row = model.tapeRow() { document.append(row) }
    }
}

#Preview("Bond — dark") {
    NavigationStack { BondScreen(document: .constant(TapeDocument())) }.parAppearance()
}

#Preview("Bond — AX5") {
    NavigationStack { BondScreen(document: .constant(TapeDocument())) }
        .environment(\.dynamicTypeSize, .accessibility5)
        .parAppearance()
}
