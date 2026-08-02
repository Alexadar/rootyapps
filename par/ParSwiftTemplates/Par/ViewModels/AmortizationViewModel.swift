import Foundation
import SwiftUI
import AmortKit

@MainActor
public final class AmortizationViewModel: ObservableObject {

    public enum Granularity: String, CaseIterable, Hashable {
        case byYear = "By year"
        case everyPeriod = "Every period"
    }

    @Published public var principal: Double = 420_000
    @Published public var annualRatePct: Double = 6.25
    @Published public var periods: Int = 360
    @Published public var periodsPerYear: Int = 12
    @Published public var balloon: Double = 0
    @Published public var granularity: Granularity = .byYear
    @Published public var expandedYear: Int?

    public init() {}

    public static let principalRange: ClosedRange<Double> = 0...1_000_000_000
    public static let ratePctRange: ClosedRange<Double> = -99...200
    public static let periodsRange: ClosedRange<Double> = 1...1_200

    /// NOTE: confirm the memberwise labels against `AmortKit/Amortization.swift`
    /// before first build — `Loan` exposes principal, periodicRate, periods,
    /// timing, rounding, balloon.
    private var loan: Amortization.Loan {
        Amortization.Loan(
            principal: principal,
            periodicRate: annualRatePct / 100 / Double(periodsPerYear),
            periods: periods,
            timing: .end,
            rounding: .cents,
            balloon: balloon
        )
    }

    public var payment: Double { Amortization.payment(loan) }
    public var totalInterest: Double { Amortization.totalInterest(loan) }
    public var schedule: [Amortization.Period] { Amortization.schedule(loan) }

    public func balance(after period: Int) -> Double {
        Amortization.balance(loan, after: period)
    }

    public func yearTotals(_ year: Int) -> Amortization.Totals {
        Amortization.totals(loan, year: year, periodsPerYear: periodsPerYear)
    }

    public var years: [Int] {
        let count = Int(ceil(Double(periods) / Double(periodsPerYear)))
        return Array(1...max(count, 1))
    }

    public func periods(inYear year: Int) -> [Amortization.Period] {
        let first = (year - 1) * periodsPerYear + 1
        let last = min(year * periodsPerYear, periods)
        guard first <= last else { return [] }
        return schedule.filter { $0.index >= first && $0.index <= last }
    }

    public var conventions: [String] {
        ["cent rounding", "payments at period end", "final payment absorbs the residue"]
    }
}
