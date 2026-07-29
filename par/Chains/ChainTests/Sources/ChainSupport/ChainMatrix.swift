import Foundation

/// The complete enumeration of Kit-to-Kit chains, and what backs each one.
///
/// Ten Kits give **90 ordered pairs**. Most are meaningless — statistics does not feed depreciation —
/// but "meaningless" is a claim, and an untested claim is how a real chain goes missing. So every one of
/// the 90 is classified here, the meaningful ones are tested, and a coverage guard fails if a pair is
/// unclassified, duplicated, or classified as tested without a test to match.
///
/// This is data, not documentation: the guard reads it.
public enum Chain {

    /// The ten Kits, as chain endpoints.
    public enum Kit: String, CaseIterable, Sendable {
        case dayCount = "DayCountKit"
        case tvm = "TVMKit"
        case amort = "AmortKit"
        case cashFlow = "CashFlowKit"
        case rate = "RateKit"
        case bond = "BondKit"
        case depreciation = "DepKit"
        case percent = "PercentKit"
        case stat = "StatKit"
        case realEstate = "RealEstateKit"
    }

    /// What backs a chain, in the taxonomy of `calculators/VALIDATION.md`.
    public enum Backing: Equatable, Sendable {
        /// An end-to-end value published by an external authority: feed the producer's published inputs
        /// in one end, and the consumer's published answer must come out the other.
        case published(String)
        /// The chain is an algebraic identity between the two Kits.
        case identity(String)
        /// The chain must satisfy a directional or structural property.
        case invariant(String)
        /// No meaningful data flows this way. The reason is recorded so the judgement can be argued with.
        case notApplicable(String)
        /// Data *would* flow this way, but something needed is not implemented yet. Recorded as a gap
        /// rather than silently classified as not-applicable.
        case gap(String)

        /// The chain id a test must declare, for the tested classifications.
        public var chainID: String? {
            switch self {
            case .published(let id), .identity(let id), .invariant(let id): return id
            case .notApplicable, .gap: return nil
            }
        }

        public var isTested: Bool { chainID != nil }
    }

    /// One ordered pair, producer → consumer.
    public struct Link: Hashable, Sendable {
        public let producer: Kit
        public let consumer: Kit
        public init(_ producer: Kit, _ consumer: Kit) {
            self.producer = producer
            self.consumer = consumer
        }
        public var description: String { "\(producer.rawValue) → \(consumer.rawValue)" }
    }

    private static func link(_ p: Kit, _ c: Kit, _ backing: Backing) -> (Link, Backing) {
        (Link(p, c), backing)
    }

    /// Every ordered pair of distinct Kits, classified. 90 entries; the guard asserts the count.
    public static let matrix: [Link: Backing] = Dictionary(
        uniqueKeysWithValues: [
            // ── DayCountKit produces day counts and dates ────────────────────────────
            link(.dayCount, .bond, .published("dates-to-bond-price")),
            link(.dayCount, .rate, .identity("dates-to-apy-term")),
            link(.dayCount, .amort, .identity("dates-to-payment-schedule")),
            link(.dayCount, .tvm, .identity("dates-to-term-in-periods")),
            link(.dayCount, .cashFlow, .identity("dates-to-flow-periods")),
            link(.dayCount, .depreciation, .invariant("dates-to-placed-in-service-convention")),
            link(.dayCount, .realEstate, .notApplicable(
                "underwriting ratios are annual and dateless; a holding period is TVM's, not this Kit's")),
            link(.dayCount, .percent, .notApplicable(
                "a markup or a break-even volume has no term: nothing in PercentKit consumes a day count")),
            link(.dayCount, .stat, .notApplicable(
                "the datasets are unordered observations; time-series work would need a lag model this Kit does not have")),

            // ── TVMKit produces payments, rates, terms and values ────────────────────
            link(.tvm, .amort, .published("tvm-payment-to-schedule")),
            link(.tvm, .cashFlow, .identity("tvm-to-npv-of-the-same-flows")),
            link(.tvm, .stat, .identity("compounded-series-to-exponential-fit")),
            link(.tvm, .realEstate, .identity("tvm-payment-to-mortgage-constant")),
            link(.tvm, .rate, .identity("tvm-periodic-rate-to-effective-rate")),
            link(.tvm, .bond, .invariant("tvm-annuity-to-bond-price-components")),
            link(.tvm, .depreciation, .notApplicable(
                "depreciation is a statutory schedule, not a discounted one; the discounting happens downstream in CashFlowKit")),
            link(.tvm, .percent, .notApplicable("no percentage-of-business quantity comes out of a TVM solve")),
            link(.tvm, .dayCount, .notApplicable("TVM counts periods, and never produces a date")),

            // ── AmortKit produces schedules, balances and interest splits ────────────
            link(.amort, .cashFlow, .identity("schedule-to-npv-equals-principal")),
            link(.amort, .tvm, .identity("remaining-balance-to-tvm-future-value")),
            link(.amort, .realEstate, .identity("schedule-to-annual-debt-service")),
            link(.amort, .rate, .published("schedule-to-apr")),
            link(.amort, .stat, .invariant("balance-series-to-regression")),
            link(.amort, .percent, .invariant("interest-share-of-payment")),
            link(.amort, .bond, .notApplicable(
                "a loan schedule is not a security's cash flow: no coupon, no redemption, no accrual convention")),
            link(.amort, .depreciation, .notApplicable("a loan balance is not a depreciable basis")),
            link(.amort, .dayCount, .notApplicable("AmortKit works in periods and produces no dates")),

            // ── CashFlowKit produces NPV, IRR and payback ────────────────────────────
            link(.cashFlow, .rate, .published("irr-to-apr")),
            link(.cashFlow, .tvm, .identity("npv-of-level-flows-to-tvm-present-value")),
            link(.cashFlow, .realEstate, .identity("npv-of-property-flows")),
            link(.cashFlow, .percent, .invariant("npv-to-profitability-index")),
            link(.cashFlow, .bond, .published("bond-price-as-npv")),
            link(.cashFlow, .amort, .notApplicable(
                "a flow vector carries no rate or term, so it cannot produce a loan to amortise")),
            link(.cashFlow, .depreciation, .notApplicable("cash flows do not determine a recovery period")),
            link(.cashFlow, .stat, .notApplicable(
                "fitting a curve to discounted flows describes the discounting, not the data")),
            link(.cashFlow, .dayCount, .notApplicable("CashFlowKit works in integer periods")),

            // ── RateKit produces APR, APY and rate conversions ───────────────────────
            link(.rate, .tvm, .published("apy-to-tvm-rate")),
            link(.rate, .amort, .published("apr-to-schedule")),
            link(.rate, .cashFlow, .published("apr-to-irr")),
            link(.rate, .bond, .identity("effective-rate-to-bond-yield")),
            link(.rate, .realEstate, .identity("rate-to-mortgage-constant")),
            link(.rate, .percent, .invariant("rate-to-percentage-change")),
            link(.rate, .depreciation, .notApplicable("no interest rate enters a MACRS schedule")),
            link(.rate, .stat, .notApplicable(
                "one rate is a scalar, not a sample; fitting a curve through rates would need a term structure this app does not model")),
            link(.rate, .dayCount, .notApplicable("RateKit consumes day counts; it does not produce dates")),

            // ── BondKit produces prices, yields, accrual and duration ────────────────
            link(.bond, .cashFlow, .published("bond-price-to-flow-vector")),
            link(.bond, .dayCount, .published("accrual-fraction-round-trip")),
            link(.bond, .tvm, .identity("bond-yield-to-tvm-discounting")),
            link(.bond, .rate, .identity("bond-yield-to-effective-rate")),
            link(.bond, .stat, .invariant("yield-curve-points-to-regression")),
            link(.bond, .percent, .invariant("price-change-to-percentage-change")),
            link(.bond, .amort, .notApplicable(
                "a bond repays principal at maturity, not on an amortisation schedule")),
            link(.bond, .depreciation, .notApplicable("securities are not depreciable property")),
            link(.bond, .realEstate, .notApplicable(
                "a bond yield is not a cap rate; comparing them is an analyst's judgement, not arithmetic")),

            // ── DepKit produces deduction schedules ──────────────────────────────────
            link(.depreciation, .cashFlow, .invariant("tax-shield-to-npv")),
            link(.depreciation, .percent, .identity("deduction-to-share-of-basis")),
            link(.depreciation, .realEstate, .gap(
                "real property uses straight line over 27.5 or 39 years under the MID-MONTH convention "
                + "(Pub 946 Tables A-6 and A-7). DepKit implements the GDS declining-balance classes only, "
                + "so a property's building basis cannot be depreciated yet. Recorded, not hidden")),
            link(.depreciation, .tvm, .notApplicable("a deduction stream has no rate to solve for")),
            link(.depreciation, .amort, .notApplicable("depreciation does not amortise a debt")),
            link(.depreciation, .rate, .notApplicable("no rate is implied by a statutory schedule")),
            link(.depreciation, .bond, .notApplicable("securities are not depreciable property")),
            link(.depreciation, .stat, .notApplicable("a 6-to-21 point statutory schedule is not a sample")),
            link(.depreciation, .dayCount, .notApplicable(
                "the placed-in-service convention is a quarter or a half-year, not a day count")),

            // ── PercentKit produces margins, prices and break-even volumes ───────────
            link(.percent, .realEstate, .identity("break-even-volume-to-break-even-occupancy")),
            link(.percent, .cashFlow, .identity("margin-to-flow-vector")),
            link(.percent, .tvm, .invariant("percentage-growth-to-compounding")),
            link(.percent, .rate, .invariant("percentage-change-to-effective-rate")),
            link(.percent, .stat, .notApplicable("a single percentage is not a dataset")),
            link(.percent, .amort, .notApplicable("a margin does not define a loan")),
            link(.percent, .bond, .notApplicable("a retail margin has no bond analogue")),
            link(.percent, .depreciation, .notApplicable("a markup is not a recovery percentage")),
            link(.percent, .dayCount, .notApplicable(
                "PercentKit produces ratios and volumes, never a date or a day count to hand onward")),

            // ── StatKit produces fits and forecasts ──────────────────────────────────
            link(.stat, .cashFlow, .identity("forecast-to-flow-vector")),
            link(.stat, .tvm, .identity("exponential-fit-to-growth-rate")),
            link(.stat, .realEstate, .invariant("rent-trend-to-noi")),
            link(.stat, .percent, .invariant("fit-slope-to-percentage-change")),
            link(.stat, .rate, .notApplicable(
                "a fitted growth rate is not a compounding convention; the conversion belongs to TVM")),
            link(.stat, .amort, .notApplicable("a regression does not define a loan")),
            link(.stat, .bond, .notApplicable(
                "curve fitting to yields is term-structure modelling, which this app does not do")),
            link(.stat, .depreciation, .notApplicable("recovery periods are statutory, never fitted")),
            link(.stat, .dayCount, .notApplicable(
                "a fit produces coefficients and forecasts, never a calendar date for DayCountKit to count from")),

            // ── RealEstateKit produces NOI, loan sizes and coverage ──────────────────
            link(.realEstate, .amort, .identity("sized-loan-to-schedule")),
            link(.realEstate, .tvm, .identity("mortgage-constant-to-tvm-payment")),
            link(.realEstate, .cashFlow, .identity("property-flows-to-npv")),
            link(.realEstate, .percent, .identity("occupancy-to-break-even")),
            link(.realEstate, .rate, .invariant("cap-rate-to-effective-yield")),
            link(.realEstate, .stat, .notApplicable("one property's ratios are not a sample")),
            link(.realEstate, .bond, .notApplicable("a mortgage is not priced as a Treasury security here")),
            link(.realEstate, .depreciation, .gap(
                "the same missing piece as DepKit → RealEstateKit: 27.5/39-year straight line under the "
                + "mid-month convention is not implemented, so a building's basis has no schedule")),
            link(.realEstate, .dayCount, .notApplicable("underwriting ratios are annual and dateless")),
        ]
    )

    /// Every ordered pair of distinct Kits — what `matrix` must cover exactly.
    public static var allLinks: [Link] {
        Kit.allCases.flatMap { producer in
            Kit.allCases.compactMap { consumer in
                producer == consumer ? nil : Link(producer, consumer)
            }
        }
    }

    /// The chain ids that must have a test.
    public static var testedChainIDs: Set<String> {
        Set(matrix.values.compactMap(\.chainID))
    }

    /// The recorded gaps — chains that would carry data if something were implemented.
    public static var gaps: [(Link, String)] {
        matrix.compactMap { link, backing in
            if case .gap(let reason) = backing { return (link, reason) }
            return nil
        }
    }
}
