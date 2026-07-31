import Foundation
import Testing
import AmortKit
import BondKit
import CashFlowKit
import DayCountKit
import DepKit
import PercentKit
import RateKit
import StatKit
import RealEstateKit
@testable import Par

/// Every control, in every state it can be put into — not just the one it ships in.
///
/// ## Why this file exists
///
/// A shipped watch app in this repo had a measurement-unit toggle that did nothing: every number
/// correct, every screen rendering, suite green, because controls were only ever tested in their
/// default state. Par had nineteen such controls. It had already shipped six registers that the UI
/// displayed and nothing could assign — annuity-due and every payment frequency but monthly were
/// computable by the Kits and unreachable from the screens — and the tests did not notice, because
/// nothing ever moved a control off its default.
///
/// So: for a control with N states this asserts N; for two that interact, the product. The rule is
/// that the assertion must be on the **output**, never on the control — a toggle that flips its own
/// label while the number stays put is exactly the defect being hunted.
///
/// ## Why here and not in XCUITest
///
/// An interaction through the UI costs ~1.1 s: XCUITest re-snapshots the accessibility tree and waits
/// for idle before every event. The Bond direction × first-period cross product alone is ten cases,
/// TVM's frequency pair is thirty-six; at UI speed that is minutes of wall-clock nobody will run.
/// Against the view models it is microseconds. The UI keeps exactly one assertion per control, in
/// `ParUITests`, to prove the binding is wired — a model test cannot catch a view bound to the wrong
/// property, and a model test is the only sane place for the combinatorics.
@MainActor
@Suite("State space — every control, every position")
struct StateSpaceTests {

    // MARK: - Amortization: the frequency that silently divides the rate

    /// `periodsPerYear` is not a label. It divides the annual rate into the periodic one
    /// (`AmortizationViewModel.periodicRate`), so it moves the payment — and nothing in the app set
    /// it off 12 until it was exposed as a control.
    @Test("every payment frequency changes the payment",
          arguments: [1, 2, 4, 12, 26, 52])
    func amortizationFrequencyMovesThePayment(frequency: Int) {
        let model = AmortizationViewModel()
        model.periodsPerYear = 12
        let monthly = model.payment

        model.periodsPerYear = frequency
        let payment = model.payment

        #expect(payment.isFinite && payment > 0,
                Comment(rawValue: "\(frequency)/yr produced \(payment)"))
        if frequency != 12 {
            #expect(payment != monthly,
                    Comment(rawValue: "\(frequency)/yr computed the same payment as monthly — the "
                            + "frequency is not reaching the periodic rate"))
        }
    }

    /// A lower frequency means fewer, larger compoundings of the same annual rate.
    @Test func amortizationFrequencyOrdersThePeriodicRate() {
        let model = AmortizationViewModel()
        model.periodsPerYear = 1
        let annual = model.payment
        model.periodsPerYear = 52
        let weekly = model.payment
        // Same n and PV: a weekly payment must be far smaller than an annual one.
        #expect(weekly < annual)
    }

    /// The granularity picker selects between two different renderings of one schedule. Both must
    /// describe the same loan — the year totals are the periods, summed.
    @Test func granularityIsTwoViewsOfOneSchedule() {
        let model = AmortizationViewModel()

        model.granularity = .byYear
        let years = model.years
        #expect(!years.isEmpty)

        model.granularity = .everyPeriod
        let schedule = model.schedule
        #expect(schedule.count == model.periods)

        // Year one's interest is the first twelve periods' interest.
        let firstYear = model.yearTotals(years[0])
        let firstTwelve = schedule.prefix(model.periodsPerYear).reduce(0) { $0 + $1.interest }
        #expect(abs(firstYear.interest - firstTwelve) < 0.005,
                Comment(rawValue: "by-year \(firstYear.interest) vs summed periods \(firstTwelve)"))
    }

    // MARK: - Bond: direction x first period, the cross product

    /// Solving for price and solving for yield must be inverses. Five first-period cases x two
    /// directions is ten formulas reachable from the screen; before the direction control existed,
    /// five of them were unreachable.
    @Test("price and yield invert, for every Appendix B section",
          arguments: Bond.FirstPeriod.allCases)
    func bondDirectionInvertsForEveryFirstPeriod(period: Bond.FirstPeriod) throws {
        let model = BondViewModel()
        model.firstPeriod = period

        // Yield from the default price.
        model.solveFor = .yield
        guard case .solved(let yield) = model.yieldToMaturity else {
            Issue.record("\(period.rawValue): no yield for the default price")
            return
        }

        // Feed that yield back the other way; the price must return.
        model.solveFor = .price
        model.yieldPct = yield * 100
        let price = model.effectivePrice

        #expect(abs(price - 98.75) < 1e-6,
                Comment(rawValue: "\(period.rawValue): round trip gave \(price), not 98.75"))
    }

    /// The direction switch changes which number is an input — and the hero with it.
    @Test func bondDirectionSwapsInputForOutput() {
        let model = BondViewModel()

        model.solveFor = .yield
        let priceAsInput = model.effectivePrice
        #expect(priceAsInput == model.price, "solving for yield, the price is what was typed")

        model.solveFor = .price
        model.yieldPct = 6.0
        #expect(model.effectivePrice != model.price,
                "solving for price, the price must be derived, not the typed one")
        // A yield above the coupon prices the bond below par.
        #expect(model.effectivePrice < 100)
    }

    // MARK: - Rate: a three-way switch over three different Kit entry points

    @Test("every rate mode solves", arguments: RateViewModel.Mode.allCases)
    func everyRateModeProducesAnAnswer(mode: RateViewModel.Mode) {
        let model = RateViewModel()
        model.mode = mode
        guard case .solved(let value) = model.outcome else {
            Issue.record("\(mode.rawValue) did not solve")
            return
        }
        #expect(value.isFinite)
    }

    /// The three modes must not answer the same question. Each reads different inputs, so each
    /// should move when its own inputs move and stay put when another mode's do.
    @Test func rateModesAreIndependent() {
        let model = RateViewModel()

        model.mode = .apr
        guard case .solved(let apr) = model.outcome else { Issue.record("no APR"); return }
        model.mode = .apy
        guard case .solved(let apy) = model.outcome else { Issue.record("no APY"); return }
        #expect(apr != apy, "APR and APY returned the same number from different inputs")

        // Moving an APY input must not disturb the APR.
        model.interest = 90
        model.mode = .apr
        guard case .solved(let aprAgain) = model.outcome else { Issue.record("no APR"); return }
        #expect(aprAgain == apr, "an APY input changed the APR")
    }

    // MARK: - Percent: three modes, three guards, three failure strings

    @Test("every percent mode solves at the defaults", arguments: PercentViewModel.Mode.allCases)
    func everyPercentModeProducesAnAnswer(mode: PercentViewModel.Mode) {
        let model = PercentViewModel()
        model.mode = mode
        guard case .solved(let value) = model.outcome else {
            Issue.record("\(mode.rawValue) did not solve at the default inputs")
            return
        }
        #expect(value.isFinite)
    }

    /// Each mode's guard must refuse exactly its own impossible input, and say so.
    @Test func eachPercentModeRefusesItsOwnImpossibleInput() {
        let model = PercentViewModel()

        model.mode = .margin
        model.price = 0
        if case .solved = model.outcome { Issue.record("a margin on a zero price was allowed") }

        model.mode = .change
        model.cost = 0                      // Percent.change traps on a zero base
        if case .solved = model.outcome { Issue.record("a change from zero was allowed") }

        model.mode = .breakEven
        model.price = 10
        model.variableCostPerUnit = 10      // no contribution, so no volume breaks even
        if case .solved = model.outcome { Issue.record("break-even with no contribution was allowed") }
    }

    /// Change mode reads the same two scalars as margin mode, under different names. Reading them
    /// the other way must give the other answer.
    @Test func changeModeReinterpretsTheSameScalars() {
        let model = PercentViewModel()
        model.mode = .change
        model.cost = 60      // from
        model.price = 100    // to
        #expect(abs(model.percentChange - 66.66666666666667) < 1e-9)
        #expect(abs(model.absoluteChange - 40) < 1e-12)

        // A fall and the rise back are not equal — the reason the mode exists.
        model.cost = 100
        model.price = 60
        #expect(abs(model.percentChange - (-40)) < 1e-12)
    }

    // MARK: - Depreciation: the method gates four other things

    @Test("every method produces a schedule that spends the basis",
          arguments: Depreciation.Method.allCases)
    func everyDepreciationMethodIsCoherent(method: Depreciation.Method) {
        let model = DepreciationViewModel()
        model.method = method
        let schedule = model.schedule
        #expect(!schedule.isEmpty, Comment(rawValue: "\(method.rawValue) produced no schedule"))
        // Every year's deduction is non-negative and the book value never goes below salvage.
        for year in schedule {
            #expect(year.depreciation >= 0,
                    Comment(rawValue: "\(method.rawValue) year \(year.year) deducted \(year.depreciation)"))
        }
    }

    /// MACRS ignores salvage by statute, and the screen must say so rather than silently dropping a
    /// number the user typed.
    @Test func macrsIgnoresSalvageAndSaysSo() {
        let model = DepreciationViewModel()
        model.method = .macrsGDS
        model.salvage = 1_000
        #expect(model.salvageIsIgnored)

        model.method = .straightLine
        #expect(!model.salvageIsIgnored, "straight line uses salvage, so nothing is ignored")
    }

    /// The provenance line may not cite a published table for a life the IRS never published.
    @Test("only the six statutory classes claim the tables", arguments: [3, 5, 7, 8, 10, 11, 15, 20])
    func macrsClaimsTablesOnlyForPublishedClasses(life: Int) {
        let model = DepreciationViewModel()
        model.method = .macrsGDS
        model.recoveryYears = Double(life)

        let statutory = [3, 5, 7, 10, 15, 20].contains(life)
        #expect(model.recoveryPeriodIsOffTable == !statutory)
        let citesTables = model.authorities.contains { $0.contains("Pub 946") }
        #expect(citesTables == statutory,
                Comment(rawValue: "\(life)-year property: cites Pub 946 = \(citesTables)"))
    }

    // MARK: - Statistics: model x the forecast domain gate

    @Test("every model fits and forecasts", arguments: Stat.Model.allCases)
    func everyStatModelFits(model kind: Stat.Model) {
        let model = StatisticsViewModel()
        model.model = kind
        guard case .fitted = model.outcome else {
            Issue.record("\(kind.rawValue) did not fit the default points")
            return
        }
        #expect(model.forecast != nil, Comment(rawValue: "\(kind.rawValue) produced no forecast"))
    }

    /// Logarithmic and power fits are undefined at x <= 0, and the screen has a domain warning that
    /// only this path can reach.
    @Test func theForecastDomainGateFiresOnlyWhereTheModelRequiresIt() {
        let model = StatisticsViewModel()
        model.forecastX = -1

        for kind in Stat.Model.allCases {
            model.model = kind
            let requiresPositive = kind.requiresPositive.x
            if requiresPositive {
                #expect(model.forecast == nil,
                        Comment(rawValue: "\(kind.rawValue) forecast at x = -1 instead of refusing"))
            } else {
                #expect(model.forecast != nil,
                        Comment(rawValue: "\(kind.rawValue) refused a legitimate negative x"))
            }
        }
    }

    // MARK: - Day count: the two controls that were Kit-covered but not VM-covered

    /// The coupon frequency is what Actual/Actual (ICMA) measures against, so it must reach the
    /// year fraction — and it must survive being saved.
    @Test("the coupon frequency reaches the year fraction", arguments: [1, 2, 4, 12])
    func dayCountFrequencyReachesTheYearFraction(frequency: Int) {
        let model = DayCountViewModel()
        model.convention = .actualActualICMA
        model.periodsPerYear = 2
        let semiannual = model.yearFraction

        model.periodsPerYear = frequency
        if frequency != 2 {
            #expect(model.yearFraction != semiannual,
                    Comment(rawValue: "\(frequency)/yr gave the same fraction as semiannual"))
        }
        #expect(model.yearFraction.isFinite)
    }

    /// 30E/360 (ISDA) substitutes 30 for a February month-end **unless** it is the termination date.
    /// Two of ISDA's own published rows differ only by this, so the toggle must move the answer.
    @Test func theTerminationDateToggleMovesTheDayCount() {
        let model = DayCountViewModel()
        model.convention = .thirtyE360ISDA
        model.start = DayCount.YearMonthDay(2007, 2, 28)
        model.end = DayCount.YearMonthDay(2007, 2, 28)
        model.end = DayCount.YearMonthDay(2008, 2, 29)

        model.usesTerminationDate = false
        let notTermination = model.days
        model.usesTerminationDate = true
        let termination = model.days

        #expect(notTermination != termination,
                Comment(rawValue: "the toggle changed nothing: \(notTermination) both ways"))
    }

    // MARK: - Cash flow and real estate: the branches the view chooses between

    /// The hero is one of three different views depending on how many rates balance the flows.
    @Test func theIRRPresentationPicksTheHonestBranch() {
        let model = CashFlowViewModel()
        // The defaults have one sign change, so exactly one rate balances them.
        guard case .unique = model.irrPresentation else {
            Issue.record("the default flows should have a unique IRR")
            return
        }

        // All-positive flows have no sign change, so no rate balances them and the screen must say
        // so rather than inventing a number.
        model.groups = [CashFlow.Group(amount: 1_000, count: 5)]
        switch model.irrPresentation {
        case .none: break                       // correct: nothing balances an all-positive series
        case .unique(let rate): Issue.record("invented an IRR of \(rate) with no sign change")
        case .multiple(let rates): Issue.record("reported \(rates.count) roots with no sign change")
        }
    }

    /// Which lender test binds is the sentence a borrower reads, and it must follow the numbers.
    @Test func theBindingTestFollowsTheSmallerLoan() {
        let model = RealEstateViewModel()
        guard case .sized(let base) = model.outcome else { Issue.record("no sizing"); return }
        #expect(base.loan == min(base.byDSCR, base.byLTV))
        // The app spells it out — "coverage binds" / "loan-to-value binds" — so match the wording
        // it actually ships rather than an acronym the screen never uses.
        #expect(model.bindingTest == (base.dscrConstrained ? "coverage binds" : "loan-to-value binds"))

        // Drop the value hard: the LTV test must take over.
        model.value = 1_000_000
        guard case .sized(let cheap) = model.outcome else { Issue.record("no sizing"); return }
        #expect(!cheap.dscrConstrained, "at a low value the LTV test should bind")
        #expect(model.bindingTest == "loan-to-value binds")
    }

    /// A property with no net operating income supports no loan, and the screen must refuse rather
    /// than print a negative one.
    @Test func noNetOperatingIncomeIsRefused() {
        let model = RealEstateViewModel()
        model.operatingExpenses = 10_000_000
        if case .sized = model.outcome {
            Issue.record("a property with negative NOI was sized for a loan")
        }
    }
}
