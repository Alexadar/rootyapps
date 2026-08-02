import Foundation
import SwiftUI
import DayCountKit

/// Dates and day counts. The screen's whole point is the comparison: the same two dates counted
/// six ways, because the convention is worth real money and is usually invisible.
@MainActor
public final class DayCountViewModel: ObservableObject {

    @Published public var start = DayCount.YearMonthDay(2026, 1, 15)
    @Published public var end = DayCount.YearMonthDay(2026, 7, 15)
    @Published public var convention: DayCount.Convention = .thirty360
    /// 30E/360 (ISDA) substitutes 30 for an end date on the last day of February *unless* it is the
    /// termination date. Two of ISDA's own published rows differ only by this.
    @Published public var usesTerminationDate = false
    /// The coupon frequency the year fraction is measured against. It was hard-coded to 2 and
    /// disclosed nowhere — and for Actual/Actual (ICMA) the fraction depends entirely on it, so a
    /// quarterly note read as a semiannual one on the very screen whose thesis is that an
    /// undisclosed convention costs money.
    @Published public var periodsPerYear: Int = 2
    @Published public var rowLabel: String = ""

    public init() {}

    public var days: Int {
        DayCount.days(from: start, to: end, convention: convention,
                      terminationDate: usesTerminationDate ? end : nil)
    }

    public var actualDays: Int { DayCount.actualDays(from: start, to: end) }

    public var yearFraction: Double {
        DayCount.yearFraction(from: start, to: end, convention: convention,
                              periodsPerYear: periodsPerYear, periodStart: start, periodEnd: end,
                              terminationDate: usesTerminationDate ? end : nil)
    }

    /// Every convention side by side — the comparison is the product.
    public var allConventions: [(convention: DayCount.Convention, days: Int)] {
        DayCount.Convention.allCases.map { candidate in
            (candidate, DayCount.days(from: start, to: end, convention: candidate,
                                      terminationDate: usesTerminationDate ? end : nil))
        }
    }

    /// The substitutions the 30/360 family applies, shown because ISDA publishes them and because a
    /// right answer reached through wrong substitutions is luck.
    public var substitution: (d1: Int, d2: Int)? {
        guard convention.isThirtyBasis else { return nil }
        return DayCount.thirtyBasisDays(from: start, to: end, convention: convention,
                                        terminationDate: usesTerminationDate ? end : nil)
    }

    public var spread: Int {
        let counts = allConventions.map(\.days)
        return (counts.max() ?? 0) - (counts.min() ?? 0)
    }

    public var isReversed: Bool { end < start }

    public var authorities: [String] {
        ["2006 ISDA Definitions §4.16", "31 CFR 356 App B §I"]
    }

    public var conventions: [String] {
        var items = [convention.displayName, "UTC calendar · no time zone",
                     "year fraction vs \(Frequency.name(for: periodsPerYear)) periods"]
        if convention == .thirtyE360ISDA {
            items.append(usesTerminationDate ? "end date IS the termination date"
                                             : "end date is not the termination date")
        }
        if spread > 0 { items.append("conventions disagree by \(spread) days here") }
        return items
    }

    public func tapeRow() -> TapeRow? {
        guard !isReversed else { return nil }
        return TapeRow(label: rowLabel, inputs: .dayCount(DayCountInputs(
            start: start.encoded, end: end.encoded,
            conventionRawValue: convention.rawValue,
            terminationDate: usesTerminationDate ? end.encoded : nil
        )))
    }
}
