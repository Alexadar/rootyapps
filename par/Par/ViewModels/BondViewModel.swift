import Foundation
import SwiftUI
import BondKit

@MainActor
public final class BondViewModel: ObservableObject {

    /// Which way round the screen is solving.
    ///
    /// Price was an input and only an input: yield, accrued interest, duration and convexity all
    /// derived from it, and `Bond.price(_:yield:)` — written and oracle-tested against Appendix B —
    /// had no caller. Quoting a security off a yield is half of what this screen is for; a new issue
    /// is priced that way, and so is anything struck off a benchmark.
    public enum SolveFor: String, CaseIterable, Hashable {
        case yield = "Yield from price"
        case price = "Price from yield"
    }

    @Published public var solveFor: SolveFor = .yield
    @Published public var couponPct: Double = 4.25
    @Published public var price: Double = 98.75
    /// The yield entered when solving for price, as a percent. `BondKit` works in fractions, so the
    /// conversion happens at this seam and never in the Kit.
    @Published public var yieldPct: Double = 4.5
    // No redemption input: BondKit prices per 100 of par and redeems at 100 (31 CFR 356 App B §II).
    // A control that silently does nothing is worse than no control.
    //
    // There was a `convention` here for the same reason `redemption` once was, and it was worse:
    // nothing assigned it, `Bond.Terms` takes no convention argument, and `TapeSolver` ignored the
    // stored value — yet the ProvenanceStrip printed it as a statement of how the number was
    // produced. Appendix B does not price off a named day-count convention; accrual is (s − r)/s
    // from the day counts entered below, and the strip now says that instead.
    /// Which of Appendix B §II's five price formulas applies. This one is real: it selects the
    /// formula, and a security priced as a reopening under `.regular` is a silently wrong number.
    @Published public var firstPeriod: Bond.FirstPeriod = .regular
    @Published public var fullPeriods: Int = 10
    @Published public var daysToNextCoupon: Int = 18
    @Published public var daysInPeriod: Int = 181
    @Published public var rowLabel: String = ""

    public init() {}

    public static let couponRange: ClosedRange<Double> = 0...20
    public static let priceRange: ClosedRange<Double> = 1...300
    /// `Bond.yieldToMaturity` searches −99%…200%; entering a yield outside it could not round-trip.
    public static let yieldRange: ClosedRange<Double> = -99...200

    private var terms: Bond.Terms {
        Bond.Terms(
            couponPct: couponPct,
            fullPeriods: fullPeriods,
            daysToNextCoupon: daysToNextCoupon,
            daysInPeriod: daysInPeriod,
            firstPeriod: firstPeriod
            // fractionalPortionDays / fractionalPortionPeriodDays are left at their defaults (0 and 1).
            // s″ must be > 0 — passing 0 satisfies the compiler and traps on the first Kit call.
        )
    }

    public enum YieldOutcome: Equatable {
        case solved(Double)
        case failed(String)
    }

    /// The price the rest of the screen derives from: the one typed, or the one solved from a yield.
    public var effectivePrice: Double {
        solveFor == .yield ? price : Bond.price(terms, yield: yieldPct / 100)
    }

    public var yieldToMaturity: YieldOutcome {
        // Solving for price makes the yield an input, so there is nothing to search for.
        if solveFor == .price { return .solved(yieldPct / 100) }
        do { return .solved(try Bond.yieldToMaturity(terms, price: price)) }
        catch let error as Bond.YieldError { return .failed(error.description) }
        catch { return .failed("No yield produces that price.") }
    }

    public var accruedInterest: Double { Bond.accruedInterest(terms) }
    /// `Bond.currentYield` returns a fraction (0.0430); the coupon is entered as a percent, so the
    /// conversion belongs here at the display seam — never in the Kit.
    public var currentYieldPct: Double {
        Bond.currentYield(couponPct: couponPct, price: effectivePrice) * 100
    }
    public var invoicePrice: Double { effectivePrice + accruedInterest }

    public func macaulayDuration(at yield: Double) -> Double { Bond.macaulayDuration(terms, yield: yield) }
    public func modifiedDuration(at yield: Double) -> Double { Bond.modifiedDuration(terms, yield: yield) }
    public func convexity(at yield: Double) -> Double { Bond.convexity(terms, yield: yield) }

    public var authorities: [String] { ["31 CFR 356 App B §II.A"] }

    /// A bond price always says how it was produced. That is the claim — so every item here has to
    /// be something the number actually depended on.
    public var conventions: [String] {
        [Self.sectionName(firstPeriod), "semiannual", "price per 100 of par",
         "\(daysInPeriod - daysToNextCoupon) / \(daysInPeriod) days accrued"]
    }

    /// Appendix B numbers its five formulas; naming the section is what makes the line checkable
    /// against the regulation.
    static func sectionName(_ period: Bond.FirstPeriod) -> String {
        switch period {
        case .regular: return "§II.A regular first period"
        case .short: return "§II.B short first period"
        case .long: return "§II.C long first period"
        case .reopenedRegular: return "§II.D reopened, regular period"
        case .reopenedLongRegularPortion: return "§II.E reopened, long first period"
        }
    }

    /// Inputs only — never the result. Day counts rather than dates, because that is how Appendix B
    /// states its formulas and how the Kit takes them.
    public func tapeRow() -> TapeRow? {
        guard case .solved = yieldToMaturity else { return nil }
        return TapeRow(label: rowLabel, inputs: .bond(BondInputs(
            couponPct: couponPct, price: effectivePrice, fullPeriods: fullPeriods,
            daysToNextCoupon: daysToNextCoupon, daysInPeriod: daysInPeriod,
            // `conventionRawValue` is retained so older tapes keep decoding; nothing reads it and
            // nothing ever did, so it is no longer given a value that implies otherwise.
            conventionRawValue: "",
            firstPeriodRawValue: firstPeriod.rawValue
        )))
    }
}

extension Bond.FirstPeriod {
    /// What fits on a card. The full section name lives in the picker and in the ProvenanceStrip.
    var shortName: String {
        switch self {
        case .regular: return "Regular"
        case .short: return "Short"
        case .long: return "Long"
        case .reopenedRegular: return "Reopened"
        case .reopenedLongRegularPortion: return "Reopened long"
        }
    }
}
