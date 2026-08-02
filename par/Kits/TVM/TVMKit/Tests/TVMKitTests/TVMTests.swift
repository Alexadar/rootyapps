import Testing
import Foundation
import TVMKit

// Oracle = 31 CFR 356 App B §II (US Treasury, public domain),
//          https://www.govinfo.gov/content/pkg/CFR-2024-title31-vol2/pdf/CFR-2024-title31-vol2-part356-appB.pdf
//          oracle-backed.
/// The two factors the whole balance equation is built from, against Treasury's published values.
///
/// ORACLES:
///  • PUBLISHED — vⁿ and aₙ from four Treasury worked examples, each printed to ten decimals.
///    Treasury computes them for its own bond-pricing formulas; they are the same discount and
///    annuity factors TVM uses, so they pin the factors independently of anything Par computes.
@Suite("Annuity and discount factors — oracle-backed")
struct FactorOracles {

    @Test("published vⁿ and aₙ", arguments: [
        "treasury-II-A-factors", "treasury-II-C-factors",
        "treasury-II-D-factors", "treasury-II-E-factors",
    ])
    func publishedFactors(id: String) {
        let o = Oracles.require(id)
        let i = o.input("periodicRate")
        let n = o.input("periods")

        let v = TVM.discountFactor(periodicRate: i, periods: n)
        #expect(o.matches("discountFactor", v), "vⁿ at i=\(i), n=\(n): got \(v)")

        let a = TVM.annuityFactor(periodicRate: i, periods: n)
        #expect(o.matches("annuityFactor", a), "aₙ at i=\(i), n=\(n): got \(a)")

        // Treasury also prints the one-period discount v for its long-first-period example.
        if o.values["onePeriodDiscount"] != nil {
            let v1 = TVM.discountFactor(periodicRate: i, periods: 1)
            #expect(o.matches("onePeriodDiscount", v1))
        }
    }

    /// Treasury's own identity: aₙ = (1 − vⁿ)/(i/2) with its semiannual rate — here, (1 − vⁿ)/i.
    @Test("aₙ = (1 − vⁿ)/i on the published pairs", arguments: [
        "treasury-II-A-factors", "treasury-II-D-factors", "treasury-II-E-factors",
    ])
    func annuityFactorIsTheClosedForm(id: String) {
        let o = Oracles.require(id)
        let i = o.input("periodicRate")
        let derived = (1 - o.value("discountFactor")) / i
        #expect(abs(derived - o.value("annuityFactor")) <= 5e-9,
                "the published pair must satisfy its own definition")
    }
}

// Oracle = 12 CFR 1026 App J (c) and 12 CFR 1030 App A (CFPB, public domain).  oracle-backed.
/// Solving for the rate — the one register with no closed form — against published answers.
///
/// ORACLES:
///  • PUBLISHED — Reg Z Appendix J (c)(1)(i), (c)(5)(ii) and (c)(5)(iv), which are exactly ordinary
///    TVM problems (no odd first period), plus Reg DD Appendix A's NOW-account yield.
@Suite("Rate solve — oracle-backed")
struct RateSolveOracles {

    @Test("published annual percentage rates", arguments: [
        "regz-appJ-c1-i-rate", "regz-appJ-c5-ii-rate",
        "regz-appJ-c5-iv-rate", "regdd-appA-now-account",
    ])
    func publishedRates(id: String) throws {
        let o = Oracles.require(id)
        let perYear = Int(o.input("paymentsPerYear"))
        let registers = TVM.Registers(
            periods: o.input("periods"),
            presentValue: o.inputs["presentValue"] ?? 0,
            payment: o.inputs["payment"] ?? 0,
            futureValue: o.inputs["futureValue"] ?? 0,
            paymentsPerYear: perYear,
            compoundsPerYear: perYear
        )
        let rate = try TVM.solve(for: .ratePct, registers)
        #expect(o.matches("annualRatePct", rate),
                "solved \(rate) against published \(o.value("annualRatePct"))")

        // And the solved rate must actually balance the equation it came from.
        let balanced = registers.setting(.ratePct, to: rate)
        let scale = max(abs(registers.presentValue), abs(registers.futureValue), 1)
        #expect(abs(TVM.residual(balanced)) <= 1e-9 * scale)
    }
}

/// The identities and invariants that make the five-register model self-consistent.
///
/// ORACLES:
///  • IDENTITY — the balance equation and the five-way round trip: solve each register from the other
///    four and recover the input.
///  • INVARIANT — annuity due vs ordinary, i = 0, i → 0, payments/yr ≠ compounds/yr, sign symmetry.
@Suite("TVM — identity and invariant")
struct TVMIdentities {

    /// A spread of realistic register sets: mortgage, car loan, savings, zero-rate, high-rate,
    /// annuity due, and mismatched frequencies.
    static let cases: [TVM.Registers] = [
        .init(periods: 360, annualRatePct: 6.5, presentValue: 400_000, payment: -2528.27,
              futureValue: 0, paymentsPerYear: 12, compoundsPerYear: 12),
        .init(periods: 60, annualRatePct: 4.9, presentValue: 32_000, payment: -602.09,
              futureValue: 0, paymentsPerYear: 12, compoundsPerYear: 12),
        .init(periods: 120, annualRatePct: 3.0, presentValue: -5_000, payment: -250,
              futureValue: 40_000, paymentsPerYear: 12, compoundsPerYear: 12),
        .init(periods: 24, annualRatePct: 0.0, presentValue: 5_000, payment: -208.3333333333333,
              futureValue: 0, paymentsPerYear: 12, compoundsPerYear: 12),
        .init(periods: 8, annualRatePct: 28.5, presentValue: 400, payment: -60,
              futureValue: 0, paymentsPerYear: 13, compoundsPerYear: 13),
        .init(periods: 36, annualRatePct: 7.25, presentValue: 20_000, payment: -600,
              futureValue: 0, paymentsPerYear: 12, compoundsPerYear: 12, timing: .begin),
        .init(periods: 300, annualRatePct: 5.25, presentValue: 250_000, payment: -1480,
              futureValue: 0, paymentsPerYear: 12, compoundsPerYear: 2),   // Canadian mortgage
        .init(periods: 4, annualRatePct: 12.0, presentValue: -1_000, payment: 0,
              futureValue: 1_268.24, paymentsPerYear: 4, compoundsPerYear: 4),
    ]

    /// The five-way round trip. For each case, make the registers exactly consistent, then solve for
    /// each register in turn from the other four and check the original value comes back.
    @Test("solve each register from the other four", arguments: cases.indices)
    func fiveWayRoundTrip(index: Int) throws {
        let seed = Self.cases[index]

        // Make the set exactly consistent first: recompute PMT (or FV when there is no payment) so
        // the residual is zero to machine precision rather than to the two decimals a human typed.
        var consistent = seed
        if seed.payment != 0 {
            consistent = seed.setting(.payment, to: try TVM.solve(for: .payment, seed))
        } else {
            consistent = seed.setting(.futureValue, to: try TVM.solve(for: .futureValue, seed))
        }
        let scale = max(abs(consistent.presentValue), abs(consistent.futureValue),
                        abs(consistent.payment) * consistent.periods, 1)
        #expect(abs(TVM.residual(consistent)) <= 1e-9 * scale, "seed did not become consistent")

        for variable in TVM.Variable.allCases {
            // A zero-rate case has nothing to recover when solving for the rate from a residual that
            // is flat in i at 0 — the rate solve returns exactly 0, which is checked separately.
            let expected = consistent.value(of: variable)
            let solved = try TVM.solve(for: variable, consistent)
            let magnitude = max(abs(expected), 1)
            #expect(abs(solved - expected) <= 1e-7 * magnitude,
                    "\(variable.rawValue): solved \(solved), expected \(expected) (case \(index))")
        }
    }

    /// Annuity due is an ordinary annuity one period earlier: PV_begin = PV_end × (1+i), exactly.
    @Test func annuityDueIsOneMorePeriodOfDiscounting() throws {
        for i in [0.0, 1e-9, 0.004, 0.05, 0.5] {
            for n in [1.0, 12.0, 360.0] {
                let end = TVM.annuityFactor(periodicRate: i, periods: n, timing: .end)
                let begin = TVM.annuityFactor(periodicRate: i, periods: n, timing: .begin)
                #expect(abs(begin - end * (1 + i)) <= 1e-12 * max(end, 1))
            }
        }

        let ordinary = TVM.Registers(periods: 36, annualRatePct: 7.25, presentValue: 20_000,
                                     futureValue: 0, paymentsPerYear: 12, compoundsPerYear: 12)
        let due = TVM.Registers(periods: 36, annualRatePct: 7.25, presentValue: 20_000,
                                futureValue: 0, paymentsPerYear: 12, compoundsPerYear: 12,
                                timing: .begin)
        let pmtEnd = try TVM.solve(for: .payment, ordinary)
        let pmtBegin = try TVM.solve(for: .payment, due)
        let i = TVM.periodicRate(ordinary)
        // Paying at the start of each period buys one period of interest: the payment shrinks by (1+i).
        #expect(abs(pmtBegin * (1 + i) - pmtEnd) <= 1e-9 * abs(pmtEnd))
        #expect(abs(pmtBegin) < abs(pmtEnd))
    }

    /// i = 0 is a real case, not an error: the annuity degenerates to n and n = −(PV+FV)/PMT.
    @Test func zeroRateDegeneratesCleanly() throws {
        #expect(TVM.annuityFactor(periodicRate: 0, periods: 24) == 24)
        #expect(TVM.discountFactor(periodicRate: 0, periods: 24) == 1)

        let r = TVM.Registers(periods: 0, annualRatePct: 0, presentValue: 5_000, payment: -250,
                              futureValue: 0, paymentsPerYear: 12, compoundsPerYear: 12)
        let n = try TVM.solve(for: .periods, r)
        #expect(abs(n - 20) <= 1e-12)

        let pmt = try TVM.solve(for: .payment,
                                TVM.Registers(periods: 20, annualRatePct: 0, presentValue: 5_000,
                                              paymentsPerYear: 12, compoundsPerYear: 12))
        #expect(abs(pmt + 250) <= 1e-12)
    }

    /// A rate of 1e-9 must not be swallowed by `1 + ε`. Compared against the series expansion of
    /// aₙ = (1 − (1+i)⁻ⁿ)/i, which is n − i·n(n+1)/2 + O(i²n³); at i = 1e-9, n = 360 the dropped
    /// term is ~5e-11, so 1e-10 is the honest tolerance.
    @Test func tinyRatesKeepTheirDigits() {
        let i = 1e-9
        let n = 360.0
        let a = TVM.annuityFactor(periodicRate: i, periods: n)
        let series = n - i * n * (n + 1) / 2
        #expect(abs(a - series) <= 1e-10, "aₙ = \(a) vs series \(series)")
        #expect(a != n, "a tiny rate must still bend the annuity factor")

        let v = TVM.discountFactor(periodicRate: i, periods: n)
        #expect(abs(v - (1 - i * n + i * i * n * (n + 1) / 2)) <= 1e-12)
        #expect(v < 1)
    }

    /// payments/yr ≠ compounds/yr: the rate is converted to the payment frequency, not divided.
    /// This is the Canadian mortgage case, and getting it wrong is the domain's classic silent error.
    @Test func paymentAndCompoundingFrequenciesConvertProperly() {
        // 6% nominal, compounded semiannually, paid monthly.
        let i = TVM.periodicRate(annualRatePct: 6, paymentsPerYear: 12, compoundsPerYear: 2)
        let expected = pow(1 + 0.06 / 2, 2.0 / 12.0) - 1
        #expect(abs(i - expected) <= 1e-15)

        // It is NOT 6%/12 — the naive answer a wrong implementation gives.
        #expect(abs(i - 0.005) > 1e-5)

        // Matching frequencies must give exactly the simple division.
        let simple = TVM.periodicRate(annualRatePct: 6, paymentsPerYear: 12, compoundsPerYear: 12)
        #expect(abs(simple - 0.005) <= 1e-16)

        // And the conversion round-trips back to the nominal rate for every frequency pair.
        for p in [1, 2, 4, 12, 26, 52, 365] {
            for c in [1, 2, 4, 12, 365] {
                let periodic = TVM.periodicRate(annualRatePct: 7.3, paymentsPerYear: p, compoundsPerYear: c)
                let back = TVM.annualRatePct(periodicRate: periodic, paymentsPerYear: p, compoundsPerYear: c)
                #expect(abs(back - 7.3) <= 1e-10, "round trip failed at p=\(p), c=\(c)")
            }
        }
    }

    /// Flipping every sign flips the answer and nothing else — the equation is homogeneous.
    @Test func signConventionIsSymmetric() throws {
        let lend = TVM.Registers(periods: 48, annualRatePct: 8, presentValue: 15_000,
                                 futureValue: 0, paymentsPerYear: 12, compoundsPerYear: 12)
        let borrow = TVM.Registers(periods: 48, annualRatePct: 8, presentValue: -15_000,
                                   futureValue: 0, paymentsPerYear: 12, compoundsPerYear: 12)
        let a = try TVM.solve(for: .payment, lend)
        let b = try TVM.solve(for: .payment, borrow)
        #expect(abs(a + b) <= 1e-12 * abs(a))
        #expect(a < 0 && b > 0, "money out is negative; money in is positive")
    }

    /// Rate solves must refuse impossible inputs rather than return a plausible number.
    @Test func impossibleInputsThrowRatherThanGuess() {
        // All cash flows the same sign: no rate can balance them.
        let allOut = TVM.Registers(periods: 12, presentValue: -1_000, payment: -100,
                                   futureValue: -100, paymentsPerYear: 12, compoundsPerYear: 12)
        #expect(throws: TVM.SolveError.noSignChange) { _ = try TVM.solve(for: .ratePct, allOut) }

        // Zero periods: there is no rate to find.
        let noPeriods = TVM.Registers(periods: 0, presentValue: 1_000, payment: -100,
                                      paymentsPerYear: 12, compoundsPerYear: 12)
        #expect(throws: (any Error).self) { _ = try TVM.solve(for: .ratePct, noPeriods) }

        // A payment too small to ever retire the balance: no positive n exists.
        let neverAmortises = TVM.Registers(periods: 0, annualRatePct: 12, presentValue: 10_000,
                                           payment: -50, futureValue: 0,
                                           paymentsPerYear: 12, compoundsPerYear: 12)
        #expect(throws: TVM.SolveError.termHasNoSolution) {
            _ = try TVM.solve(for: .periods, neverAmortises)
        }

        // Zero rate and zero payment amortise nothing.
        let nothingHappens = TVM.Registers(periods: 0, annualRatePct: 0, presentValue: 1_000,
                                           payment: 0, futureValue: 0,
                                           paymentsPerYear: 12, compoundsPerYear: 12)
        #expect(throws: (any Error).self) { _ = try TVM.solve(for: .periods, nothingHappens) }
    }

    /// A payment exactly equal to the interest is a perpetuity: the balance never moves.
    @Test func interestOnlyPaymentNeverAmortises() {
        let r = TVM.Registers(periods: 0, annualRatePct: 6, presentValue: 100_000,
                              payment: -500, futureValue: 0,   // 6%/12 × 100,000 = 500
                              paymentsPerYear: 12, compoundsPerYear: 12)
        #expect(throws: TVM.SolveError.termHasNoSolution) { _ = try TVM.solve(for: .periods, r) }
    }

    /// Monotonicity: a higher rate means a higher payment, and a longer term a lower one.
    @Test func paymentIsMonotoneInRateAndTerm() throws {
        var previousByRate = 0.0
        for rate in [0.0, 1.0, 3.0, 6.5, 12.0, 24.0] {
            let pmt = try TVM.solve(for: .payment,
                                    .init(periods: 360, annualRatePct: rate, presentValue: 400_000,
                                          paymentsPerYear: 12, compoundsPerYear: 12))
            #expect(abs(pmt) > previousByRate, "payment must rise with the rate")
            previousByRate = abs(pmt)
        }

        var previousByTerm = Double.infinity
        for n in [60.0, 120.0, 240.0, 360.0] {
            let pmt = try TVM.solve(for: .payment,
                                    .init(periods: n, annualRatePct: 6.5, presentValue: 400_000,
                                          paymentsPerYear: 12, compoundsPerYear: 12))
            #expect(abs(pmt) < previousByTerm, "payment must fall as the term lengthens")
            previousByTerm = abs(pmt)
        }
    }

    /// A known mortgage payment, to three decimals, computed the long way round: the standard
    /// annuity formula written out independently of the Kit's factor helpers.
    @Test func paymentMatchesAnIndependentlyWrittenAnnuityFormula() throws {
        let principal = 400_000.0, annual = 6.5, n = 360.0
        let i = annual / 100 / 12
        let independent = -principal * i / (1 - pow(1 + i, -n))
        let solved = try TVM.solve(for: .payment,
                                   .init(periods: n, annualRatePct: annual, presentValue: principal,
                                         paymentsPerYear: 12, compoundsPerYear: 12))
        #expect(abs(solved - independent) <= 1e-9 * abs(independent))
    }
}
