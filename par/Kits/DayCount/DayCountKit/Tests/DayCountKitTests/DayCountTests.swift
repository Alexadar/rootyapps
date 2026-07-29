import Testing
import Foundation
import DayCountKit

/// Support: the corpus encodes dates as yyyyMMdd doubles so the suites hold no date literals.
extension Oracle {
    func date(_ key: String) -> DayCount.YearMonthDay { decode(input(key)) }

    private func decode(_ encoded: Double) -> DayCount.YearMonthDay {
        let n = Int(encoded.rounded())
        return DayCount.YearMonthDay(n / 10000, (n / 100) % 100, n % 100)
    }
}

// Oracle = ISDA, 30-360-2006ISDADefs.xls (2006 ISDA Definitions §4.16(f)/(g)/(h)),
//          https://www.isda.org/a/mIJEE/30-360-2006ISDADefs.xls.  oracle-backed.
/// The 30/360 family against ISDA's own published examples.
///
/// ORACLES:
///  • PUBLISHED — all 22 Comparison-sheet date pairs, checked on the day count **and** on the D1/D2
///    substitution each convention applies, because ISDA publishes both and a right total reached
///    through wrong substitutions is luck, not correctness.
///  • PUBLISHED — the termination-date exception of §4.16(h), which is the only reason two of those
///    rows differ from the rest.
@Suite("30/360 conventions — oracle-backed")
struct ThirtyThreeSixtyOracles {

    private static let conventions: [(DayCount.Convention, String)] = [
        (.thirty360, "thirty360"),
        (.thirtyE360, "thirtyE360"),
        (.thirtyE360ISDA, "thirtyE360ISDA"),
    ]

    @Test("every published date pair, every 30/360 variant", arguments: Oracles.isdaRows.map(\.id))
    func publishedDayCounts(id: String) {
        let o = Oracles.require(id)
        let start = o.date("start"), end = o.date("end")
        let termination = DayCount.YearMonthDay(2009, 2, 28)   // the sheet's own termination date

        for (convention, key) in Self.conventions {
            let days = DayCount.days(
                from: start, to: end, convention: convention, terminationDate: termination
            )
            let published = o.values["days_\(key)"] ?? .nan
            #expect(o.matches("days_\(key)", Double(days)),
                    "\(convention.displayName) \(start)→\(end): got \(days), published \(published)")

            let (d1, d2) = DayCount.thirtyBasisDays(
                from: start, to: end, convention: convention, terminationDate: termination
            )
            #expect(o.matches("d1_\(key)", Double(d1)), "\(convention.displayName) D1 \(start)→\(end)")
            #expect(o.matches("d2_\(key)", Double(d2)), "\(convention.displayName) D2 \(start)→\(end)")
        }

        let actual = DayCount.actualDays(from: start, to: end)
        #expect(o.matches("days_actual", Double(actual)), "actual days \(start)→\(end)")
    }

    /// §4.16(h)'s termination-date exception, isolated. Both rows are in the published corpus; the
    /// only difference between them is whether the end date *is* the termination date.
    @Test func terminationDateExceptionIsHonoured() {
        let feb2009 = DayCount.YearMonthDay(2009, 2, 28)

        // 2008-08-31 → 2009-02-28 with 2009-02-28 as the termination date: D2 stays 28 → 178 days.
        let asTermination = Oracles.require("isda-3060-2008-08-31-2009-02-28")
        let withTermination = DayCount.days(
            from: asTermination.date("start"), to: asTermination.date("end"),
            convention: .thirtyE360ISDA, terminationDate: feb2009
        )
        #expect(asTermination.matches("days_thirtyE360ISDA", Double(withTermination)))
        #expect(withTermination == 178)

        // The same end-of-February end date when it is *not* the termination date: D2 → 30.
        let notTermination = Oracles.require("isda-3060-2006-08-31-2007-02-28")
        let without = DayCount.days(
            from: notTermination.date("start"), to: notTermination.date("end"),
            convention: .thirtyE360ISDA, terminationDate: feb2009
        )
        #expect(notTermination.matches("days_thirtyE360ISDA", Double(without)))
        #expect(without == 180)

        // Dropping the termination date entirely must change the first answer — proving the
        // parameter is load-bearing and not decorative.
        let ignoringTermination = DayCount.days(
            from: asTermination.date("start"), to: asTermination.date("end"),
            convention: .thirtyE360ISDA, terminationDate: nil
        )
        #expect(ignoringTermination == 180)
        #expect(ignoringTermination != withTermination)
    }

    /// ISDA's own footnote: under Bond Basis the two halves of a year can sum to 361.
    @Test func bondBasisYearCanSumTo361() {
        let o = Oracles.require("isda-bond-basis-361-day-year")
        let start = o.date("start"), mid = o.date("mid"), end = o.date("end")

        let first = DayCount.days(from: start, to: mid, convention: .thirty360)
        let second = DayCount.days(from: mid, to: end, convention: .thirty360)
        #expect(o.matches("firstHalf_thirty360", Double(first)))
        #expect(o.matches("secondHalf_thirty360", Double(second)))
        #expect(o.matches("year_thirty360", Double(first + second)))

        for (convention, key) in [(DayCount.Convention.thirtyE360, "year_thirtyE360"),
                                  (.thirtyE360ISDA, "year_thirtyE360ISDA")] {
            let sum = DayCount.days(from: start, to: mid, convention: convention)
                + DayCount.days(from: mid, to: end, convention: convention)
            #expect(o.matches(key, Double(sum)), "\(convention.displayName) year should close at 360")
        }
    }
}

// Oracle = 31 CFR 356 App B §I.D(2) (US Treasury, public domain).  oracle-backed.
/// Treasury's actual/actual half-years — the day counts its accrued-interest example is built on.
///
/// ORACLES:
///  • PUBLISHED — 44 days of a 181-day half-year and 81 days of a 184-day half-year, from the
///    reopening example Treasury prints in full.
@Suite("Treasury half-years — oracle-backed")
struct TreasuryHalfYearOracles {

    @Test func fortyFourDaysOfA181DayHalfYear() {
        let o = Oracles.require("treasury-halfyear-44-of-181")
        let accrual = DayCount.actualDays(from: o.date("accrualStart"), to: o.date("periodEnd"))
        let period = DayCount.actualDays(from: o.date("periodStart"), to: o.date("periodEnd"))
        #expect(o.matches("accrualDays", Double(accrual)))
        #expect(o.matches("periodDays", Double(period)))
    }

    @Test func eightyOneDaysOfA184DayHalfYear() {
        let o = Oracles.require("treasury-halfyear-81-of-184")
        let accrual = DayCount.actualDays(from: o.date("periodStart"), to: o.date("settlement"))
        let period = DayCount.actualDays(from: o.date("periodStart"), to: o.date("periodEnd"))
        #expect(o.matches("accrualDays", Double(accrual)))
        #expect(o.matches("periodDays", Double(period)))

        // The accrual fraction Treasury multiplies its daily figure by.
        let fraction = DayCount.accrualFraction(
            periodStart: o.date("periodStart"),
            settlement: o.date("settlement"),
            periodEnd: o.date("periodEnd")
        )
        #expect(abs(fraction - 81.0 / 184.0) <= 1e-15)
    }
}

/// Calendar identities and the boundaries this domain actually breaks on.
///
/// ORACLES:
///  • IDENTITY — the proleptic Gregorian leap rule and the serial/date round trip.
///  • INVARIANT — additivity, month-end clamping, year and century boundaries, ordering.
@Suite("Calendar — identity and invariant")
struct CalendarInvariants {

    @Test func gregorianLeapRule() {
        #expect(DayCount.isLeapYear(2000))            // divisible by 400
        #expect(!DayCount.isLeapYear(1900))           // century, not divisible by 400
        #expect(!DayCount.isLeapYear(2100))
        #expect(DayCount.isLeapYear(2024))
        #expect(!DayCount.isLeapYear(2023))
        #expect(DayCount.daysInMonth(year: 2024, month: 2) == 29)
        #expect(DayCount.daysInMonth(year: 2023, month: 2) == 28)
        #expect(DayCount.daysInYear(2024) == 366)
        #expect(DayCount.daysInYear(2023) == 365)
    }

    @Test func serialRoundTripsOverFourCenturies() {
        var date = DayCount.YearMonthDay(1800, 1, 1)
        let last = DayCount.YearMonthDay(2200, 1, 1)
        var previous = date.serial - 1
        while date < last {
            #expect(DayCount.date(serial: date.serial) == date)
            #expect(date.serial == previous + 1, "serials must advance by exactly one day at \(date)")
            previous = date.serial
            date = DayCount.date(date, byAdding: 1)
        }
    }

    @Test func knownWeekdays() {
        // 1970-01-01 was a Thursday; 2000-01-01 a Saturday; 2026-07-27 a Monday.
        #expect(DayCount.weekdayIndex(DayCount.YearMonthDay(1970, 1, 1)) == 4)
        #expect(DayCount.weekdayIndex(DayCount.YearMonthDay(2000, 1, 1)) == 6)
        #expect(DayCount.weekdayIndex(DayCount.YearMonthDay(2026, 7, 27)) == 1)
    }

    @Test func actualDaysIsAdditiveAndSigned() {
        let a = DayCount.YearMonthDay(2019, 11, 30)
        let b = DayCount.YearMonthDay(2020, 2, 29)
        let c = DayCount.YearMonthDay(2021, 3, 1)
        #expect(DayCount.actualDays(from: a, to: b) + DayCount.actualDays(from: b, to: c)
                == DayCount.actualDays(from: a, to: c))
        #expect(DayCount.actualDays(from: b, to: a) == -DayCount.actualDays(from: a, to: b))
        #expect(DayCount.actualDays(from: a, to: a) == 0)
    }

    @Test func thirtyBasisDayCountsAreAdditiveAcrossAMonthBoundary() {
        // The 30/360 numerator is additive when the split date is not month-end sensitive.
        let a = DayCount.YearMonthDay(2020, 1, 15)
        let b = DayCount.YearMonthDay(2020, 4, 15)
        let c = DayCount.YearMonthDay(2020, 7, 15)
        for convention in DayCount.Convention.allCases where convention.isThirtyBasis {
            let split = DayCount.days(from: a, to: b, convention: convention)
                + DayCount.days(from: b, to: c, convention: convention)
            #expect(split == DayCount.days(from: a, to: c, convention: convention))
        }
    }

    @Test func addingMonthsClampsToMonthEnd() {
        let jan31 = DayCount.YearMonthDay(2020, 1, 31)
        #expect(DayCount.date(jan31, byAddingMonths: 1) == DayCount.YearMonthDay(2020, 2, 29))
        #expect(DayCount.date(jan31, byAddingMonths: 13) == DayCount.YearMonthDay(2021, 2, 28))
        // Clamping is not reversible, and the doc comment says so.
        let clamped = DayCount.date(jan31, byAddingMonths: 1)
        #expect(DayCount.date(clamped, byAddingMonths: 1) == DayCount.YearMonthDay(2020, 3, 29))
        // Negative months and year rollover.
        #expect(DayCount.date(DayCount.YearMonthDay(2020, 3, 31), byAddingMonths: -1)
                == DayCount.YearMonthDay(2020, 2, 29))
        #expect(DayCount.date(DayCount.YearMonthDay(2020, 1, 15), byAddingMonths: -1)
                == DayCount.YearMonthDay(2019, 12, 15))
        #expect(DayCount.date(DayCount.YearMonthDay(2020, 1, 15), byAddingMonths: -13)
                == DayCount.YearMonthDay(2018, 12, 15))
    }

    @Test func addingDaysCrossesLeapDayAndYearEnd() {
        #expect(DayCount.date(DayCount.YearMonthDay(2020, 2, 28), byAdding: 1)
                == DayCount.YearMonthDay(2020, 2, 29))
        #expect(DayCount.date(DayCount.YearMonthDay(2019, 2, 28), byAdding: 1)
                == DayCount.YearMonthDay(2019, 3, 1))
        #expect(DayCount.date(DayCount.YearMonthDay(2020, 12, 31), byAdding: 1)
                == DayCount.YearMonthDay(2021, 1, 1))
        #expect(DayCount.date(DayCount.YearMonthDay(2021, 1, 1), byAdding: -1)
                == DayCount.YearMonthDay(2020, 12, 31))
    }

    @Test func yearFractionDenominatorsDifferAsAdvertised() {
        let start = DayCount.YearMonthDay(2020, 1, 1)
        let end = DayCount.YearMonthDay(2021, 1, 1)   // 366 actual days (2020 is a leap year)
        #expect(DayCount.actualDays(from: start, to: end) == 366)
        #expect(abs(DayCount.yearFraction(from: start, to: end, convention: .actual360)
                    - 366.0 / 360.0) <= 1e-15)
        #expect(abs(DayCount.yearFraction(from: start, to: end, convention: .actual365Fixed)
                    - 366.0 / 365.0) <= 1e-15)
        #expect(abs(DayCount.yearFraction(from: start, to: end, convention: .thirty360) - 1.0) <= 1e-15)
        // Actual/Actual (ICMA) over one full semiannual period is exactly 1/2 a year.
        let mid = DayCount.YearMonthDay(2020, 7, 1)
        #expect(abs(DayCount.yearFraction(from: start, to: mid, convention: .actualActualICMA,
                                         periodsPerYear: 2, periodStart: start, periodEnd: mid)
                    - 0.5) <= 1e-15)
    }

    @Test func isoParsingRejectsImpossibleDates() {
        #expect(DayCount.YearMonthDay(iso: "2020-02-29") == DayCount.YearMonthDay(2020, 2, 29))
        #expect(DayCount.YearMonthDay(iso: "2019-02-29") == nil)
        #expect(DayCount.YearMonthDay(iso: "2020-13-01") == nil)
        #expect(DayCount.YearMonthDay(iso: "2020-00-10") == nil)
        #expect(DayCount.YearMonthDay(iso: "not a date") == nil)
        #expect(DayCount.YearMonthDay(iso: "2020-06-31") == nil)
    }

    @Test func monthEndPredicates() {
        #expect(DayCount.YearMonthDay(2020, 2, 29).isLastDayOfFebruary)
        #expect(DayCount.YearMonthDay(2019, 2, 28).isLastDayOfFebruary)
        #expect(!DayCount.YearMonthDay(2020, 2, 28).isLastDayOfFebruary)
        #expect(DayCount.YearMonthDay(2020, 4, 30).isLastDayOfMonth)
        #expect(!DayCount.YearMonthDay(2020, 4, 29).isLastDayOfMonth)
    }

    @Test func conventionMetadataIsComplete() {
        for convention in DayCount.Convention.allCases {
            #expect(!convention.displayName.isEmpty)
            #expect(!convention.rawValue.isEmpty)
        }
        #expect(DayCount.Convention.allCases.count == 6)
    }
}
