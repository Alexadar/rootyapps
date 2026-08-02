import Testing
import Foundation
import CashFlowKit

/// Enforcement guard for the oracle corpus, per `calculators/VALIDATION.md`.
///
/// ORACLES:
///  • GUARD — structural only.
@Suite("Oracle corpus integrity")
struct OracleGuardTests {

    @Test func everyOracleCitesAnExternalSource() {
        for o in Oracles.all {
            #expect(!o.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(o.source.contains("http"), "oracle '\(o.id)' has no URI")
            #expect(o.source.contains("CFR") || o.source.contains("NIST"),
                    "oracle '\(o.id)' names no document")
            #expect(!o.inputs.isEmpty)
            #expect(!o.precision.isEmpty, "oracle '\(o.id)' has no precision rationale")
        }
    }

    @Test func everyValueHasAMatchingTolerance() {
        for o in Oracles.all {
            #expect(!o.values.isEmpty)
            for key in o.values.keys {
                #expect(o.tolerances[key] != nil, "'\(o.id)'.\(key) has no tolerance")
                #expect((o.tolerances[key] ?? -1) > 0, "'\(o.id)'.\(key) tolerance must be positive")
            }
            for key in o.tolerances.keys { #expect(o.values[key] != nil) }
        }
    }

    @Test func oracleIDsAreUniqueAndResolvable() {
        let ids = Oracles.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for o in Oracles.all { #expect(Oracles.require(o.id).id == o.id) }
    }

    /// Coverage guard: IRR is the measure with no closed form and the only one that can silently
    /// return a wrong answer, so the corpus must carry several published cases — including ones with
    /// irregular first and final payments, not just level ones.
    @Test func irrHasPublishedCasesIncludingIrregularPayments() {
        let irrOracles = Oracles.all.filter { $0.values["annualPct"] != nil }
        #expect(irrOracles.count >= 5)
        #expect(irrOracles.contains { $0.inputs["firstPayment"] != nil }, "no irregular-first case")
        #expect(irrOracles.contains { $0.inputs["finalPayment"] != nil }, "no irregular-final case")
    }
}

// Oracle = 12 CFR 1026 App J (c) (CFPB, public domain).  oracle-backed.
/// IRR against Regulation Z's published annual percentage rates.
///
/// ORACLES:
///  • PUBLISHED — five Appendix J examples with no odd first period, so every flow lands on an integer
///    period boundary and the published APR is w × the periodic IRR. Level, irregular-first,
///    irregular-final, both-irregular, and single-payment.
///  • IDENTITY — NPV at the recovered IRR is zero.
@Suite("IRR — oracle-backed")
struct IRROracles {

    /// Rebuild an Appendix J example's flow vector from the corpus inputs.
    private func flows(_ o: Oracle) -> [Double] {
        var flows: [Double] = [-o.input("advance")]
        if let first = o.inputs["firstPayment"] { flows.append(first) }
        if let payment = o.inputs["payment"] {
            flows.append(contentsOf: CashFlow.expand([.init(amount: payment, count: Int(o.input("count")))]))
        } else if o.inputs["firstPayment"] == nil, o.inputs["finalPayment"] != nil {
            // (c)(5)(iv): a single payment, `count` periods away, with nothing in between.
            let gap = Int(o.input("count"))
            if gap > 1 { flows.append(contentsOf: Array(repeating: 0, count: gap - 1)) }
        }
        if let final = o.inputs["finalPayment"], o.inputs["payment"] != nil || o.inputs["count"] != nil {
            if o.inputs["payment"] == nil {
                // single-payment case: it lands two periods out (n = 2 in the published example)
                flows.append(0)
                flows.append(final)
            } else {
                flows.append(final)
            }
        }
        return flows
    }

    @Test("published annual percentage rates as IRRs", arguments: [
        "regz-appJ-c1-i-irr", "regz-appJ-c2-i-irr", "regz-appJ-c3-i-irr",
        "regz-appJ-c4-i-irr", "regz-appJ-c5-iv-irr",
    ])
    func publishedIRRs(id: String) throws {
        let o = Oracles.require(id)
        let vector = flows(o)
        let result = CashFlow.irr(flows: vector)
        let periodic = try #require(result.rate, "expected a unique IRR for \(id), got \(result)")

        let annualised = periodic * o.input("unitPeriodsPerYear") * 100
        #expect(o.matches("annualPct", annualised),
                "\(id): got \(annualised)%, published \(o.value("annualPct"))%")

        // The recovered rate must actually zero the NPV — the identity that makes it an IRR at all.
        let scale = vector.reduce(0) { $0 + abs($1) }
        #expect(abs(CashFlow.npv(rate: periodic, flows: vector)) <= 1e-9 * scale)
    }
}

// Oracle = NIST HB 135e2025 §7.1.1 (public domain).  oracle-backed.
/// Life-cycle cost composition against NIST's own worked example.
///
/// ORACLES:
///  • PUBLISHED — Example 7-1's two totals and the net saving between them.
@Suite("Life-cycle cost — oracle-backed")
struct LifeCycleCostOracles {

    @Test func stormWindowExample() {
        let o = Oracles.require("nist-hb135-ex7-1-lcc")

        func energyPresentValue(therms: Double, kWh: Double) -> Double {
            therms * o.input("gasPricePerTherm") * o.input("gasUPV")
                + kWh * o.input("electricityPricePerKWh") * o.input("electricityUPV")
        }

        let base = energyPresentValue(therms: o.input("baseThermsPerYear"), kWh: o.input("baseKWhPerYear"))
        let alternative = o.input("initialCost")
            + energyPresentValue(therms: o.input("altThermsPerYear"), kWh: o.input("altKWhPerYear"))

        #expect(o.matches("baseCaseLCC", base), "base case LCC \(base)")
        #expect(o.matches("alternativeLCC", alternative), "alternative LCC \(alternative)")
        #expect(o.matches("netSavings", base - alternative))
        #expect(alternative < base, "NIST's conclusion: the storm windows are cost effective")
    }
}

/// The identities and invariants NPV, IRR, MIRR and payback must satisfy.
///
/// ORACLES:
///  • IDENTITY — NPV(IRR) = 0; NPV is linear in the flows; UPV is the closed form of a level annuity;
///    NFV is NPV carried forward.
///  • INVARIANT — monotonicity in the rate, multiple sign changes reported honestly, zero and tiny
///    rates, grouped entry equals flat entry, MIRR agrees with IRR where it must.
@Suite("Cash flows — identity and invariant")
struct CashFlowIdentities {

    static let conventional: [[Double]] = [
        [-1000, 300, 300, 300, 300],
        [-5000, 230, 230, 230, 230, 230, 230, 230, 230, 230, 230, 230, 230],
        [-250_000, 30_000, 35_000, 40_000, 45_000, 200_000],
        [-1, 2],
    ]

    @Test("NPV is zero at the IRR", arguments: conventional.indices)
    func npvIsZeroAtTheIRR(index: Int) throws {
        let flows = Self.conventional[index]
        let rate = try #require(CashFlow.irr(flows: flows).rate)
        let scale = flows.reduce(0) { $0 + abs($1) }
        #expect(abs(CashFlow.npv(rate: rate, flows: flows)) <= 1e-10 * scale)
    }

    @Test func npvIsLinearInTheFlowsAndMonotoneInTheRate() {
        let a: [Double] = [-1000, 400, 400, 400]
        let b: [Double] = [-500, 100, 200, 300]
        let sum = zip(a, b).map(+)
        for rate in [0.0, 0.01, 0.08, 0.5] {
            let combined = CashFlow.npv(rate: rate, flows: sum)
            let separate = CashFlow.npv(rate: rate, flows: a) + CashFlow.npv(rate: rate, flows: b)
            #expect(abs(combined - separate) <= 1e-9 * max(abs(combined), 1))
        }

        // For conventional flows (one sign change), NPV falls strictly as the rate rises.
        var previous = Double.infinity
        for rate in [0.0, 0.02, 0.05, 0.1, 0.25, 0.5, 1.0] {
            let value = CashFlow.npv(rate: rate, flows: a)
            #expect(value < previous)
            previous = value
        }
    }

    @Test func npvAtZeroIsTheSumAndUPVIsTheClosedForm() {
        let flows: [Double] = [-1000, 300, 300, 300, 300]
        #expect(abs(CashFlow.npv(rate: 0, flows: flows) - 200) <= 1e-12)

        for rate in [0.0, 1e-9, 0.004, 0.07, 0.5] {
            for n in [1.0, 12.0, 360.0] {
                let upv = CashFlow.uniformPresentValue(rate: rate, periods: n)
                let byNPV = CashFlow.npv(rate: rate, flows: [0] + Array(repeating: 1.0, count: Int(n)))
                #expect(abs(upv - byNPV) <= 1e-9 * max(upv, 1),
                        "UPV \(upv) vs summed NPV \(byNPV) at r=\(rate), n=\(n)")
            }
        }
        #expect(CashFlow.uniformPresentValue(rate: 0, periods: 240) == 240)
    }

    @Test func nfvIsNpvCarriedForward() {
        let flows: [Double] = [-1000, 300, 300, 300, 300]
        for rate in [0.0, 0.03, 0.2] {
            let expected = CashFlow.npv(rate: rate, flows: flows) * pow(1 + rate, 4)
            #expect(abs(CashFlow.nfv(rate: rate, flows: flows) - expected) <= 1e-9 * max(abs(expected), 1))
        }
    }

    @Test func groupedEntryMatchesFlatEntry() {
        let grouped = CashFlow.expand([.init(amount: -1000, count: 1), .init(amount: 250, count: 6)])
        #expect(grouped == [-1000, 250, 250, 250, 250, 250, 250])
        #expect(abs(CashFlow.npv(rate: 0.05, flows: grouped)
                    - CashFlow.npv(rate: 0.05, flows: [-1000, 250, 250, 250, 250, 250, 250])) <= 1e-12)
    }

    /// The failure that matters: flows with two sign changes have two IRRs, and reporting one of them
    /// as "the" answer is a lie. The classic textbook shape — spend, earn, spend.
    @Test func multipleSignChangesAreReportedHonestly() {
        let flows: [Double] = [-4000, 25_000, -25_000]
        guard case .multiple(let roots) = CashFlow.irr(flows: flows) else {
            Issue.record("expected multiple IRRs, got \(CashFlow.irr(flows: flows))")
            return
        }
        #expect(roots.count == 2, "found \(roots)")
        let scale = flows.reduce(0) { $0 + abs($1) }
        for root in roots {
            #expect(abs(CashFlow.npv(rate: root, flows: flows)) <= 1e-8 * scale,
                    "root \(root) does not zero the NPV")
        }
        #expect(roots[0] < roots[1])
        // And `rate` must refuse to pick one.
        #expect(CashFlow.irr(flows: flows).rate == nil)
    }

    @Test func noSignChangeMeansNoIRR() {
        #expect(CashFlow.irr(flows: [-100, -100, -100]) == .none)
        #expect(CashFlow.irr(flows: [100, 100, 100]) == .none)
        #expect(CashFlow.irr(flows: [-100]) == .none)
        #expect(CashFlow.irr(flows: []) == .none)
    }

    /// A rate of exactly zero is a legitimate IRR: pay 1000, get 1000 back.
    @Test func zeroIRRIsFound() throws {
        let rate = try #require(CashFlow.irr(flows: [-1000, 500, 500]).rate)
        #expect(abs(rate) <= 1e-9)
    }

    /// MIRR must agree with IRR when the finance and reinvestment rates *are* the IRR — the one case
    /// where the two definitions coincide.
    @Test func mirrAgreesWithIRRAtTheIRR() throws {
        for flows in Self.conventional {
            let irr = try #require(CashFlow.irr(flows: flows).rate)
            let mirr = try #require(CashFlow.mirr(flows: flows, financeRate: irr, reinvestRate: irr))
            #expect(abs(mirr - irr) <= 1e-8 * max(abs(irr), 1),
                    "MIRR \(mirr) vs IRR \(irr) for \(flows)")
        }
    }

    @Test func mirrIsMonotoneInTheReinvestmentRate() throws {
        let flows: [Double] = [-1000, 300, 300, 300, 300]
        var previous = -1.0
        for reinvest in [0.0, 0.02, 0.05, 0.1, 0.3] {
            let mirr = try #require(CashFlow.mirr(flows: flows, financeRate: 0.05, reinvestRate: reinvest))
            #expect(mirr > previous, "MIRR must rise with the reinvestment rate")
            previous = mirr
        }
        #expect(CashFlow.mirr(flows: [-100, -100], financeRate: 0.05, reinvestRate: 0.05) == nil,
                "no positive flows: MIRR is undefined, not zero")
    }

    @Test func paybackInterpolatesAndDiscountedPaybackIsLater() throws {
        // 1000 out, 400 a year in: cumulative turns positive part way through year 3.
        let flows: [Double] = [-1000, 400, 400, 400, 400]
        let plain = try #require(CashFlow.payback(flows: flows))
        #expect(abs(plain - 2.5) <= 1e-12, "payback \(plain)")

        let discounted = try #require(CashFlow.discountedPayback(flows: flows, rate: 0.10))
        #expect(discounted > plain, "discounting delays payback")
        #expect(discounted < 4)

        // Discounted payback at a zero rate is plain payback.
        let atZero = try #require(CashFlow.discountedPayback(flows: flows, rate: 0))
        #expect(abs(atZero - plain) <= 1e-12)

        // Never paying back is nil, not a large number.
        #expect(CashFlow.payback(flows: [-1000, 100, 100]) == nil)
        // An investment that pays for itself immediately pays back at zero.
        #expect(CashFlow.payback(flows: [500, 100]) == 0)
    }

    /// Tiny rates must not collapse to the zero-rate branch.
    @Test func tinyRatesStillDiscount() {
        let flows: [Double] = [-1000, 500, 500, 500]
        let atTiny = CashFlow.npv(rate: 1e-9, flows: flows)
        let atZero = CashFlow.npv(rate: 0, flows: flows)
        #expect(atTiny < atZero, "1e-9 still discounts: \(atTiny) vs \(atZero)")
        #expect(abs(atTiny - atZero) < 1e-4)
        #expect(CashFlow.discountFactor(rate: 1e-9, period: 360) < 1)
        #expect(CashFlow.discountFactor(rate: 0, period: 360) == 1)
    }
}
