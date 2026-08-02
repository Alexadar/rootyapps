import Testing
import Foundation
import ChainSupport

/// The guard that turns "we tested the chains" into a claim that can fail.
///
/// Ten Kits give 90 ordered pairs. This suite asserts that **every one of the 90 is classified** in
/// `Chain.matrix`, that every classification marked as tested has a test declared against it here, and
/// that no test claims a chain the matrix doesn't have. Add an eleventh Kit and 20 new pairs appear
/// unclassified; add a chain id to a test without adding it to the matrix and this fails too.
///
/// ORACLES:
///  • GUARD — structural only; asserts nothing about the arithmetic.
@Suite("Chain coverage")
struct ChainCoverageTests {

    /// Every chain id exercised by a test in this target, declared by hand so the guard has something
    /// independent to compare the matrix against.
    static let declaredInTests: Set<String> = [
        // PublishedChainTests — 10
        "dates-to-bond-price",
        "accrual-fraction-round-trip",
        "bond-price-as-npv",
        "bond-price-to-flow-vector",
        "tvm-payment-to-schedule",
        "schedule-to-apr",
        "apr-to-schedule",
        "irr-to-apr",
        "apr-to-irr",
        "apy-to-tvm-rate",

        // IdentityChainTests — 26
        "dates-to-apy-term",
        "dates-to-payment-schedule",
        "dates-to-term-in-periods",
        "dates-to-flow-periods",
        "tvm-to-npv-of-the-same-flows",
        "compounded-series-to-exponential-fit",
        "exponential-fit-to-growth-rate",
        "tvm-payment-to-mortgage-constant",
        "mortgage-constant-to-tvm-payment",
        "tvm-periodic-rate-to-effective-rate",
        "rate-to-mortgage-constant",
        "schedule-to-npv-equals-principal",
        "remaining-balance-to-tvm-future-value",
        "schedule-to-annual-debt-service",
        "sized-loan-to-schedule",
        "npv-of-level-flows-to-tvm-present-value",
        "npv-of-property-flows",
        "property-flows-to-npv",
        "effective-rate-to-bond-yield",
        "bond-yield-to-effective-rate",
        "bond-yield-to-tvm-discounting",
        "deduction-to-share-of-basis",
        "break-even-volume-to-break-even-occupancy",
        "occupancy-to-break-even",
        "margin-to-flow-vector",
        "forecast-to-flow-vector",

        // InvariantChainTests — 14
        "dates-to-placed-in-service-convention",
        "rate-to-percentage-change",
        "tvm-annuity-to-bond-price-components",
        "balance-series-to-regression",
        "interest-share-of-payment",
        "npv-to-profitability-index",
        "yield-curve-points-to-regression",
        "price-change-to-percentage-change",
        "tax-shield-to-npv",
        "percentage-growth-to-compounding",
        "percentage-change-to-effective-rate",
        "rent-trend-to-noi",
        "fit-slope-to-percentage-change",
        "cap-rate-to-effective-yield",
    ]

    /// All 90 ordered pairs are classified — exactly once each, with nothing extra.
    @Test func everyOrderedPairIsClassified() {
        let expected = Set(Chain.allLinks)
        #expect(expected.count == 90, "10 Kits give 90 ordered pairs, found \(expected.count)")

        let classified = Set(Chain.matrix.keys)
        let missing = expected.subtracting(classified).map(\.description).sorted()
        let extra = classified.subtracting(expected).map(\.description).sorted()
        #expect(missing.isEmpty, "unclassified chains: \(missing.joined(separator: ", "))")
        #expect(extra.isEmpty, "chains classified that do not exist: \(extra.joined(separator: ", "))")
        #expect(Chain.matrix.count == 90)
    }

    /// Every tested classification has a test, and every declared test has a classification.
    @Test func matrixAndTestsAgree() {
        let inMatrix = Chain.testedChainIDs
        let untested = inMatrix.subtracting(Self.declaredInTests).sorted()
        let undeclared = Self.declaredInTests.subtracting(inMatrix).sorted()
        #expect(untested.isEmpty, "classified as tested but no test declares them: \(untested)")
        #expect(undeclared.isEmpty, "tests declare chains the matrix does not classify: \(undeclared)")
    }

    /// Chain ids are unique across the matrix: two different pairs sharing an id would let one test
    /// stand in for a chain nobody exercised.
    @Test func chainIDsAreUnique() {
        let ids = Chain.matrix.values.compactMap(\.chainID)
        #expect(Set(ids).count == ids.count, "a chain id is used by more than one pair")
    }

    /// Every not-applicable judgement carries a reason, and every reason is a sentence rather than a
    /// shrug — the classification has to be arguable to be worth anything.
    @Test func everyDismissalIsJustified() {
        for (link, backing) in Chain.matrix {
            switch backing {
            case .notApplicable(let reason), .gap(let reason):
                #expect(reason.count > 30,
                        "\(link.description) is dismissed with too little reason: \"\(reason)\"")
            case .published, .identity, .invariant:
                continue
            }
        }
    }

    /// The composition of the matrix, asserted so a silent drift toward "not applicable" is visible.
    @Test func theBalanceOfTheMatrixIsWhatWeThinkItIs() {
        var published = 0, identity = 0, invariant = 0, notApplicable = 0, gaps = 0
        for backing in Chain.matrix.values {
            switch backing {
            case .published: published += 1
            case .identity: identity += 1
            case .invariant: invariant += 1
            case .notApplicable: notApplicable += 1
            case .gap: gaps += 1
            }
        }
        #expect(published == 10, "published chains: \(published)")
        #expect(identity == 26, "identity chains: \(identity)")
        #expect(invariant == 14, "invariant chains: \(invariant)")
        #expect(gaps == 2, "recorded gaps: \(gaps)")
        #expect(notApplicable == 38, "not-applicable pairs: \(notApplicable)")
        #expect(published + identity + invariant + notApplicable + gaps == 90)
    }

    /// The recorded gaps are real work, not decoration: each names what is missing.
    @Test func gapsNameWhatIsMissing() {
        let gaps = Chain.gaps
        #expect(gaps.count == 2)
        for (link, reason) in gaps {
            #expect(reason.contains("27.5") || reason.contains("39"),
                    "\(link.description): a gap must say what is missing — \"\(reason)\"")
        }
        // Both gaps are the same missing feature seen from two directions.
        #expect(Set(gaps.map(\.0.description)) == [
            "DepKit → RealEstateKit", "RealEstateKit → DepKit",
        ])
    }
}
