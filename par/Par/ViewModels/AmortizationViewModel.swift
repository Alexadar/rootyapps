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
    @Published public var rowLabel: String = ""

    public init() {}

    // Ranges must respect the Kit's preconditions, not merely look reasonable:
    // Amortization.Loan requires principal > 0, so 0 is not an enterable value.
    public static let principalRange: ClosedRange<Double> = 0.01...1_000_000_000
    public static let ratePctRange: ClosedRange<Double> = -99...200
    public static let periodsRange: ClosedRange<Double> = 1...1_200

    private var loan: Amortization.Loan {
        Amortization.Loan(
            principal: principal,
            periodicRate: annualRatePct / 100 / Double(periodsPerYear),
            periods: periods,
            timing: .end,
            rounding: .currency(decimals: 2),
            balloon: balloon
        )
    }

    public var payment: Double { Amortization.payment(loan) }
    public var totalInterest: Double { Amortization.totalInterest(loan) }
    public var schedule: [Amortization.Period] { Amortization.schedule(loan) }

    /// The Kit requires `0...periods`; clamping here means a stale expanded-row index or an
    /// out-of-range scrub can never trap the app.
    public func balance(after period: Int) -> Double {
        Amortization.balance(loan, after: min(max(period, 0), periods))
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

    public var authorities: [String] { ["12 CFR 1026 App J (c)(1)(i)"] }

    public var conventions: [String] {
        ["rounded to cents", "payments at period end", "final payment absorbs the residue"]
    }

    /// Inputs only — never the result. The rounding policy is part of the input, because it changes
    /// every figure in the schedule.
    public func tapeRow() -> TapeRow? {
        guard principal > 0, periods > 0, periodsPerYear > 0 else { return nil }
        return TapeRow(label: rowLabel, inputs: .amortization(AmortInputs(
            principal: principal, annualRatePct: annualRatePct, periods: periods,
            periodsPerYear: periodsPerYear, balloon: balloon, roundingDecimals: 2,
            balanceAfterPeriod: nil
        )))
    }
}
