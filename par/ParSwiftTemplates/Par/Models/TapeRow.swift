import Foundation

/// A tape line is a solved problem, not a keystroke.
///
/// The document stores INPUTS ONLY. Reopening re-runs the Kit and must reproduce
/// the stored result exactly; the Kits guarantee their half (every input type
/// round-trips losslessly, decoding validates and throws instead of trapping,
/// solves are bit-for-bit deterministic — see `ReplayTests.swift` in each Kit).
/// Our half: never cache a result we cannot regenerate, and never let a decode
/// failure crash — surface it as a damaged line the user can see and fix.
public struct TapeRow: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    /// Free text, empty most of the time and long occasionally. This is what
    /// turns a tape into a client record.
    public var label: String
    public var inputs: SolveInputs
    public let createdAt: Date

    public init(id: UUID = UUID(), label: String = "", inputs: SolveInputs, createdAt: Date = .now) {
        self.id = id
        self.label = label
        self.inputs = inputs
        self.createdAt = createdAt
    }
}

/// The input payload for each Kit surface. Add a case per Kit; never add a case
/// that stores a computed number.
public enum SolveInputs: Codable, Equatable, Sendable {
    case tvm(TVMInputs)
    case amortization(AmortInputs)
    case cashFlow(CashFlowInputs)
    case bond(BondInputs)
    /// A line whose stored inputs failed to decode. It is kept, shown, and made
    /// fixable — never silently dropped and never replaced with a guess.
    case damaged(DamagedLine)

    public var toolName: String {
        switch self {
        case .tvm: return "TVM"
        case .amortization: return "Amort"
        case .cashFlow: return "Cash Flow"
        case .bond: return "Bond"
        case .damaged: return "Damaged"
        }
    }
}

public struct TVMInputs: Codable, Equatable, Sendable {
    public var periods: Double
    public var annualRatePct: Double
    public var presentValue: Double
    public var payment: Double
    public var futureValue: Double
    public var paymentsPerYear: Int
    public var compoundsPerYear: Int
    public var timingIsBeginning: Bool
    /// Which of the five is derived. The other four are the givens.
    public var solveFor: String

    public init(periods: Double, annualRatePct: Double, presentValue: Double, payment: Double,
                futureValue: Double, paymentsPerYear: Int = 12, compoundsPerYear: Int = 12,
                timingIsBeginning: Bool = false, solveFor: String) {
        self.periods = periods
        self.annualRatePct = annualRatePct
        self.presentValue = presentValue
        self.payment = payment
        self.futureValue = futureValue
        self.paymentsPerYear = paymentsPerYear
        self.compoundsPerYear = compoundsPerYear
        self.timingIsBeginning = timingIsBeginning
        self.solveFor = solveFor
    }
}

public struct AmortInputs: Codable, Equatable, Sendable {
    public var principal: Double
    public var annualRatePct: Double
    public var periods: Int
    public var periodsPerYear: Int
    public var balloon: Double
    public var roundsToCents: Bool
    /// nil = whole-schedule totals; set = "balance after k".
    public var balanceAfterPeriod: Int?
}

public struct CashFlowInputs: Codable, Equatable, Sendable {
    public struct Group: Codable, Equatable, Sendable {
        public var amount: Double
        public var count: Int
    }
    public var groups: [Group]
    public var discountRatePct: Double
    public var financeRatePct: Double
    public var reinvestRatePct: Double
}

public struct BondInputs: Codable, Equatable, Sendable {
    public var couponPct: Double
    public var price: Double
    public var redemption: Double
    public var settlement: DateComponents
    public var maturity: DateComponents
    public var lastCoupon: DateComponents
    public var conventionRawValue: String
}

/// What we keep when a line will not decode. Enough to show the user what broke
/// and to let them repair it in place.
public struct DamagedLine: Codable, Equatable, Sendable {
    public var toolName: String
    public var reason: String
    public var rawSummary: String
}
