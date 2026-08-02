import Foundation
import SwiftUI
import DepKit

/// Depreciation, including the MACRS schedules US tax requires.
@MainActor
public final class DepreciationViewModel: ObservableObject {

    @Published public var cost: Double = 10_000
    @Published public var salvage: Double = 0
    @Published public var recoveryYears: Double = 7
    @Published public var factor: Double = 2
    @Published public var method: Depreciation.Method = .macrsGDS
    @Published public var convention: Depreciation.Convention = .halfYear
    @Published public var rowLabel: String = ""

    public init() {}

    // The Kit requires cost > 0, 0 ≤ salvage ≤ cost, recoveryYears ≥ 1, factor > 0.
    public static let costRange: ClosedRange<Double> = 0.01...1_000_000_000
    public static let salvageRange: ClosedRange<Double> = 0...1_000_000_000
    public static let recoveryRange: ClosedRange<Double> = 1...50
    public static let factorRange: ClosedRange<Double> = 1...3

    /// MACRS ignores salvage by statute; the Kit refuses an asset that carries one, so the screen
    /// tells the user rather than silently dropping the number they typed.
    public var salvageIsIgnored: Bool { method == .macrsGDS && salvage > 0 }

    /// The recovery periods the IRS actually publishes a GDS table for.
    ///
    /// `DepKit.macrsFactor` knows only these six and otherwise falls through to a 200% factor, so an
    /// 8-year MACRS asset used to render table percentages — and cite "Tables A-1 … A-5" — for a
    /// column Publication 946 does not contain. The provenance line is the product; it cannot name a
    /// table that was never printed.
    public static let macrsClasses: [Int] = [3, 5, 7, 10, 15, 20]

    /// True when the entered life has no published GDS column.
    public var recoveryPeriodIsOffTable: Bool {
        method == .macrsGDS && !Self.macrsClasses.contains(Int(recoveryYears))
    }

    private var asset: Depreciation.Asset {
        Depreciation.Asset(
            cost: max(cost, 0.01),
            salvage: method == .macrsGDS ? 0 : min(max(salvage, 0), max(cost, 0.01)),
            recoveryYears: max(Int(recoveryYears), 1),
            factor: max(factor, 0.01)
        )
    }

    public var schedule: [Depreciation.Year] {
        Depreciation.schedule(asset, method: method, convention: convention)
    }

    public var firstYear: Double { schedule.first?.depreciation ?? 0 }
    public var totalDepreciation: Double { schedule.reduce(0) { $0 + $1.depreciation } }

    /// The published percentage for each year, when the method is MACRS. This is the number a tax
    /// preparer checks against the IRS table, so it is shown, not hidden behind the dollars.
    public var macrsPercentages: [Double]? {
        guard method == .macrsGDS else { return nil }
        return Depreciation.macrsPercentages(recoveryYears: max(Int(recoveryYears), 1),
                                             convention: convention)
    }

    public var crossoverYear: Int? {
        guard method == .decliningBalanceWithCrossover || method == .decliningBalance else { return nil }
        return Depreciation.crossoverYear(asset)
    }

    public var authorities: [String] {
        guard method == .macrsGDS else { return ["definition"] }
        // Only claim the tables when the entered life is one they actually cover.
        return recoveryPeriodIsOffTable
            ? ["IRC §168 declining balance", "no published GDS table for this life"]
            : ["IRS Pub 946 (2025) App A", "Tables A-1 … A-5"]
    }

    public var conventions: [String] {
        var items: [String] = [method.displayName]
        if method == .macrsGDS {
            items.append(convention.displayName)
            items.append("salvage ignored, by statute")
            // Two published columns disagree with their own rules by one unit in the last place.
            // A user reconciling against the IRS table deserves to know before they wonder.
            if isAnomalousColumn {
                items.append("⚠︎ this published column has a known 0.01 pp anomaly")
            }
        } else {
            items.append("straight-line salvage floor")
        }
        return items
    }

    /// The two columns whose published percentages the rounding-carry method does not reproduce
    /// exactly (verified against Pub 946 pp. 71–72; see `par/scratch/SOURCES.md` §4).
    public var isAnomalousColumn: Bool {
        let years = Int(recoveryYears)
        return (convention == .midQuarterFirst && years == 20)
            || (convention == .midQuarterSecond && years == 7)
    }

    public func tapeRow() -> TapeRow? {
        guard cost > 0 else { return nil }
        return TapeRow(label: rowLabel, inputs: .depreciation(DepInputs(
            cost: cost, salvage: salvage, recoveryYears: max(Int(recoveryYears), 1),
            factor: factor, methodRawValue: method.rawValue,
            conventionRawValue: convention.rawValue
        )))
    }
}
