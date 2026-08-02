import Foundation
import SwiftUI
import BondKit
import DayCountKit

@MainActor
public final class BondViewModel: ObservableObject {

    @Published public var couponPct: Double = 4.25
    @Published public var price: Double = 98.75
    @Published public var redemption: Double = 100
    @Published public var convention: DayCount.Convention = .actualActual
    @Published public var fullPeriods: Int = 10
    @Published public var daysToNextCoupon: Int = 18
    @Published public var daysInPeriod: Int = 181
    @Published public var rowLabel: String = ""

    public init() {}

    public static let couponRange: ClosedRange<Double> = 0...20
    public static let priceRange: ClosedRange<Double> = 1...300

    /// NOTE: confirm the `Terms` initialiser labels against
    /// `BondKit/Bond.swift` before first build. The fields are couponPct,
    /// fullPeriods, daysToNextCoupon, daysInPeriod, firstPeriod,
    /// fractionalPortionDays, fractionalPortionPeriodDays.
    private var terms: Bond.Terms {
        Bond.Terms(
            couponPct: couponPct,
            fullPeriods: fullPeriods,
            daysToNextCoupon: daysToNextCoupon,
            daysInPeriod: daysInPeriod,
            firstPeriod: .regular,
            fractionalPortionDays: 0,
            fractionalPortionPeriodDays: 0
        )
    }

    public enum YieldOutcome: Equatable {
        case solved(Double)
        case failed(String)
    }

    public var yieldToMaturity: YieldOutcome {
        do { return .solved(try Bond.yieldToMaturity(terms, price: price)) }
        catch let error as Bond.YieldError { return .failed(error.description) }
        catch { return .failed("No yield produces that price.") }
    }

    public var accruedInterest: Double { Bond.accruedInterest(terms) }
    public var currentYield: Double { Bond.currentYield(couponPct: couponPct, price: price) }
    public var invoicePrice: Double { price + accruedInterest }

    public func macaulayDuration(at yield: Double) -> Double { Bond.macaulayDuration(terms, yield: yield) }
    public func modifiedDuration(at yield: Double) -> Double { Bond.modifiedDuration(terms, yield: yield) }
    public func convexity(at yield: Double) -> Double { Bond.convexity(terms, yield: yield) }

    /// A bond price always says its day-count convention. That is the claim.
    public var conventions: [String] {
        [convention.rawValue, "semiannual", "regular first period",
         "\(daysInPeriod - daysToNextCoupon) / \(daysInPeriod) days accrued"]
    }
}
