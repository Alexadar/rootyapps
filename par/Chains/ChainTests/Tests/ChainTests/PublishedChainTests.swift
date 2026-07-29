import Testing
import Foundation
import ChainSupport
import DayCountKit
import TVMKit
import AmortKit
import CashFlowKit
import RateKit
import BondKit

/// Support: the chain oracles state dates as tuples; the Kits want `YearMonthDay`.
private func ymd(_ date: (Int, Int, Int)) -> DayCount.YearMonthDay {
    DayCount.YearMonthDay(date.0, date.1, date.2)
}

// Oracle = 31 CFR 356 App B §II and 12 CFR 1026 App J / 1030 App A (public domain).  oracle-backed.
/// Chains with a published value at **both** ends.
///
/// These are the tests no single Kit can run. Appendix B states each bond example in dates *and* in the
/// r and s derived from them; Appendix J states a loan in dollars *and* in the APR derived from it. Feed
/// the published input into the producer, hand its output to the consumer, and the published answer must
/// come out — with the intermediate value checked on the way, so a compensating pair of errors cannot
/// hide.
///
/// ORACLES:
///  • PUBLISHED — 10 chains, listed by id in `Chain.matrix`.
@Suite("Published chains — oracle-backed")
struct PublishedChainTests {

    // MARK: DayCountKit → BondKit  ·  dates-to-bond-price

    /// The chain that matters most: settlement and coupon **dates** → r and s → a published price. Every
    /// one of Appendix B's five section II cases, end to end.
    @Test("dates → day counts → published price",
          arguments: ChainOracles.treasuryDatedExamples.map(\.id))
    func datesToBondPrice(id: String) {
        let o = ChainOracles.require("dates-to-bond-price")
        guard let example = ChainOracles.treasuryDatedExamples.first(where: { $0.id == id }) else {
            Issue.record("no dated example \(id)"); return
        }

        // Step 1 — DayCountKit turns the published dates into the published day counts.
        let r = DayCount.actualDays(from: ymd(example.settlement), to: ymd(example.nextCoupon))
        let s = DayCount.actualDays(from: ymd(example.periodStart), to: ymd(example.nextCoupon))
        #expect(r == example.publishedR, "§\(id): r computed \(r), published \(example.publishedR)")
        #expect(s == example.publishedS, "§\(id): s computed \(s), published \(example.publishedS)")

        var rPrime = 0, sDoublePrime = 1
        if let (accrualStart, fractionalPeriodStart) = example.fractionalPortion {
            // §II.E: r′ runs from the original issue date to the start of the regular portion, and s″ is
            // the semiannual period that ends there.
            rPrime = DayCount.actualDays(from: ymd(accrualStart), to: ymd(example.periodStart))
            sDoublePrime = DayCount.actualDays(from: ymd(fractionalPeriodStart), to: ymd(example.periodStart))
            #expect(rPrime == example.publishedRPrime, "§\(id): r′ \(rPrime)")
            #expect(sDoublePrime == example.publishedSDoublePrime, "§\(id): s″ \(sDoublePrime)")
        }

        // Step 2 — BondKit prices from those day counts. Which of the five formulas applies is part of
        // the published example, not something the chain infers.
        let firstPeriod: Bond.FirstPeriod
        switch id {
        case "II-A": firstPeriod = .regular
        case "II-B": firstPeriod = .short
        case "II-C": firstPeriod = .long
        case "II-D": firstPeriod = .reopenedRegular
        default: firstPeriod = .reopenedLongRegularPortion
        }

        let terms = Bond.Terms(
            couponPct: example.couponPct, fullPeriods: example.fullPeriods,
            daysToNextCoupon: r, daysInPeriod: s, firstPeriod: firstPeriod,
            fractionalPortionDays: rPrime, fractionalPortionPeriodDays: sDoublePrime
        )
        let quote = Bond.quote(terms, yield: example.yield)

        let tolerance = id == "II-E" ? 5e-6 : 5e-7
        #expect(abs(quote.price - example.publishedPrice) <= tolerance,
                "§\(id): priced \(quote.price) from its own dates, published \(example.publishedPrice)")
        #expect(abs(quote.accruedInterest - example.publishedAccrued) <= tolerance,
                "§\(id): accrued \(quote.accruedInterest), published \(example.publishedAccrued)")

        _ = o   // the corpus row exists so the coverage guard can see this chain is oracle-backed
    }

    /// The whole set must be exercised, not a convenient subset.
    @Test func everyPublishedBondCaseIsChained() {
        let o = ChainOracles.require("dates-to-bond-price")
        #expect(o.matches("exampleCount", Double(ChainOracles.treasuryDatedExamples.count)))
        #expect(Set(ChainOracles.treasuryDatedExamples.map(\.id)) == ["II-A", "II-B", "II-C", "II-D", "II-E"])
    }

    // MARK: BondKit → DayCountKit  ·  accrual-fraction-round-trip

    /// The reverse direction: BondKit's accrued interest must be exactly the accrual fraction DayCountKit
    /// derives from the same dates, times the semiannual coupon.
    @Test func accrualFractionRoundTrip() {
        let o = ChainOracles.require("accrual-fraction-round-trip")
        // §II.D: accrues from 1985-11-15, settles 1985-11-29, next coupon 1986-05-15.
        let periodStart = DayCount.YearMonthDay(1985, 11, 15)
        let settlement = DayCount.YearMonthDay(1985, 11, 29)
        let periodEnd = DayCount.YearMonthDay(1986, 5, 15)

        let elapsed = DayCount.actualDays(from: periodStart, to: settlement)
        let periodDays = DayCount.actualDays(from: periodStart, to: periodEnd)
        #expect(o.matches("elapsedDays", Double(elapsed)))
        #expect(o.matches("periodDays", Double(periodDays)))

        let fraction = DayCount.accrualFraction(
            periodStart: periodStart, settlement: settlement, periodEnd: periodEnd
        )
        let accruedFromDayCount = fraction * (9.50 / 2)
        #expect(o.matches("accruedInterest", accruedFromDayCount),
                "day-count route gives \(accruedFromDayCount)")

        // BondKit's own accrual, from the day counts, must be the identical Double.
        let terms = Bond.Terms(couponPct: 9.50, fullPeriods: 19,
                               daysToNextCoupon: periodDays - elapsed, daysInPeriod: periodDays,
                               firstPeriod: .reopenedRegular)
        #expect(Bond.accruedInterest(terms) == accruedFromDayCount,
                "the two Kits must agree exactly, not approximately")
    }

    // MARK: CashFlowKit ↔ BondKit  ·  bond-price-as-npv, bond-price-to-flow-vector

    /// A bond price *is* a net present value. Discounting the same coupons with CashFlowKit must
    /// reproduce Appendix B's published price — which also pins Treasury's `n` convention, since the
    /// flow vector needs n + 1 coupons.
    @Test func bondPriceAsNetPresentValue() {
        let o = ChainOracles.require("bond-price-as-npv")
        let couponsPerFlow = 8.75 / 2
        let n = 59
        let periodic = o.value("periodicYield")          // i/2 = .0442

        // n + 1 coupons, redemption with the last one; flows[0] = 0 because the price is what we solve for.
        var flows: [Double] = [0]
        for period in 1...(n + 1) {
            flows.append(period == n + 1 ? couponsPerFlow + 100 : couponsPerFlow)
        }
        #expect(o.matches("coupons", Double(flows.count - 1)))

        let npv = CashFlow.npv(rate: periodic, flows: flows)
        #expect(o.matches("price", npv), "NPV route gives \(npv)")

        // …and BondKit's closed form must land on the same number.
        let terms = Bond.Terms(couponPct: 8.75, fullPeriods: n, daysToNextCoupon: 184, daysInPeriod: 184)
        #expect(abs(Bond.price(terms, yield: 0.0884) - npv) <= 1e-9,
                "the two routes must agree to floating point, not to a tolerance")
    }

    /// The other direction: take BondKit's price and yield, build the flow vector, and confirm the
    /// implied IRR is the periodic yield — the seam a portfolio screen would cross.
    @Test func bondPriceToFlowVector() throws {
        let o = ChainOracles.require("bond-price-to-flow-vector")
        let terms = Bond.Terms(couponPct: 8.75, fullPeriods: 59, daysToNextCoupon: 184, daysInPeriod: 184)
        let price = Bond.price(terms, yield: 0.0884)
        #expect(o.matches("price", price))

        var flows: [Double] = [-price]
        for period in 1...60 { flows.append(period == 60 ? 8.75 / 2 + 100 : 8.75 / 2) }

        let irr = try #require(CashFlow.irr(flows: flows).rate)
        #expect(abs(irr - 0.0442) <= 1e-9, "the flow vector's IRR is the semiannual yield: \(irr)")
        #expect(abs(irr * 2 - 0.0884) <= 1e-9, "…and twice it is the published nominal yield")
    }

    // MARK: TVMKit → AmortKit  ·  tvm-payment-to-schedule

    /// Solve a payment in TVMKit, amortise it in AmortKit: the published payment must appear in both,
    /// and the schedule built from it must close.
    @Test func tvmPaymentToSchedule() throws {
        let o = ChainOracles.require("tvm-payment-to-schedule")
        let principal = o.value("principal")
        let annualRate = o.value("annualRatePct")
        let periods = Int(o.value("periods"))

        let solved = try TVM.solve(for: .payment, .init(
            periods: Double(periods), annualRatePct: annualRate, presentValue: principal,
            futureValue: 0, paymentsPerYear: 12, compoundsPerYear: 12
        ))
        #expect(o.matches("payment", abs(solved)), "TVM solved \(solved)")

        let loan = Amortization.Loan(
            principal: principal, periodicRate: annualRate / 100 / 12, periods: periods
        )
        #expect(abs(Amortization.payment(loan) - abs(solved)) <= 1e-9,
                "the two Kits must produce the same payment for the same loan")

        let rows = Amortization.schedule(loan)
        #expect(rows.count == periods)
        #expect(abs(rows.last!.balance) <= 1e-9, "the schedule must close")
        #expect(abs(rows.reduce(0) { $0 + $1.principal } - principal) <= 1e-9)
    }

    // MARK: AmortKit → RateKit  ·  schedule-to-apr

    /// Take the schedule's own payments and ask RateKit what rate they imply. It must be the published
    /// APR — which is Appendix J's example read backwards through two Kits.
    @Test func scheduleToAPR() throws {
        let o = ChainOracles.require("schedule-to-apr")
        let loan = Amortization.Loan(principal: 5_000, periodicRate: 0.0969 / 12, periods: 24)
        let rows = Amortization.schedule(loan)

        let payments = rows.enumerated().map { index, row in
            Rate.Payment(amount: row.payment, fullPeriods: index + 1)
        }
        let apr = try Rate.aprActuarial(
            advances: [.init(amount: loan.principal, fullPeriods: 0)],
            payments: payments, unitPeriodsPerYear: 12
        )
        #expect(o.matches("aprPct", apr), "the schedule implies \(apr)%")
    }

    // MARK: RateKit → AmortKit  ·  apr-to-schedule

    /// And forwards: a published APR must produce the published payment.
    @Test func aprToSchedule() {
        let o = ChainOracles.require("apr-to-schedule")
        let loan = Amortization.Loan(principal: 5_000, periodicRate: 0.0969 / 12, periods: 24)
        #expect(o.matches("payment", Amortization.payment(loan)))
    }

    // MARK: CashFlowKit → RateKit and RateKit → CashFlowKit  ·  irr-to-apr, apr-to-irr

    /// Appendix J (b)(1) *defines* the APR as the unit-period rate times the periods in a year. So for an
    /// example with no odd first period, RateKit's actuarial APR and CashFlowKit's IRR are two routes to
    /// one published number — and they must agree with each other far more tightly than either agrees
    /// with the published two decimals.
    @Test func irrToAPR() throws {
        let o = ChainOracles.require("irr-to-apr")
        var flows: [Double] = [-5_000]
        flows.append(contentsOf: Array(repeating: 230.0, count: 24))

        let irr = try #require(CashFlow.irr(flows: flows).rate)
        let aprFromIRR = irr * o.value("unitPeriodsPerYear") * 100
        #expect(o.matches("aprPct", aprFromIRR), "IRR route gives \(aprFromIRR)%")

        let aprFromRate = try Rate.aprActuarial(
            advances: [.init(amount: 5_000, fullPeriods: 0)],
            payments: Rate.series(amount: 230, count: 24, firstAtFullPeriods: 1),
            unitPeriodsPerYear: 12
        )
        #expect(abs(aprFromRate - aprFromIRR) <= 1e-9,
                "two implementations of the same definition: \(aprFromRate) vs \(aprFromIRR)")
    }

    /// The reverse: RateKit's periodic rate, handed to CashFlowKit, must zero the NPV of the same flows.
    @Test func aprToIRR() throws {
        let o = ChainOracles.require("apr-to-irr")
        let apr = try Rate.aprActuarial(
            advances: [.init(amount: 5_000, fullPeriods: 0)],
            payments: Rate.series(amount: 230, count: 24, firstAtFullPeriods: 1),
            unitPeriodsPerYear: 12
        )
        #expect(o.matches("aprPct", apr))

        var flows: [Double] = [-5_000]
        flows.append(contentsOf: Array(repeating: 230.0, count: 24))
        let periodic = apr / 100 / 12
        #expect(abs(CashFlow.npv(rate: periodic, flows: flows)) <= 1e-6,
                "the APR's periodic rate must zero the NPV: \(CashFlow.npv(rate: periodic, flows: flows))")
    }

    // MARK: RateKit → TVMKit  ·  apy-to-tvm-rate

    /// Regulation DD's annual percentage yield is what a single-period TVM solve must return for the same
    /// deposit — the same published 6.17% from two Kits that share no code.
    @Test func apyToTVMRate() throws {
        let o = ChainOracles.require("apy-to-tvm-rate")
        let apy = Rate.apy(
            interest: o.value("interest"), principal: o.value("principal"),
            daysInTerm: o.value("daysInTerm")
        )
        #expect(o.matches("apyPct", apy), "RateKit gives \(apy)%")

        let tvmRate = try TVM.solve(for: .ratePct, .init(
            periods: 1, presentValue: -o.value("principal"),
            futureValue: o.value("principal") + o.value("interest"),
            paymentsPerYear: 1, compoundsPerYear: 1
        ))
        #expect(o.matches("apyPct", tvmRate), "TVMKit gives \(tvmRate)%")
        #expect(abs(tvmRate - apy) <= 1e-9, "the two Kits must agree to floating point")
    }
}
