import Foundation

/// Calendar day-count conventions and the date arithmetic every other Kit dates on.
/// Pure, stateless.
///
/// MODEL CAVEAT: all arithmetic runs on a fixed **UTC Gregorian** calendar. There is no locale, no
/// time zone and no DST anywhere in this Kit — a settlement date is a calendar date, not an instant.
/// Callers hand in `YearMonthDay` values, so a device's region can never move a coupon.
public enum DayCount {

    // MARK: - Conventions

    /// The day-count conventions Par supports.
    ///
    /// The three 30/360 variants are the 2006 ISDA Definitions §4.16(f), (g) and (h). They are
    /// genuinely different: §4.16(f) and (g) disagree whenever the end date is the 31st, and
    /// §4.16(h) additionally substitutes 30 for the last day of February — except on the
    /// termination date, which is why `days(from:to:convention:terminationDate:)` takes one.
    public enum Convention: String, CaseIterable, Sendable, Codable {
        /// 30/360, "Bond Basis" — 2006 ISDA Definitions §4.16(f).
        case thirty360
        /// 30E/360, "Eurobond Basis" — §4.16(g); ICMA Rule 251 / FBF, and the version Excel uses.
        case thirtyE360
        /// 30E/360 (ISDA) — §4.16(h); the only 30E/360 in the 2000 Definitions.
        case thirtyE360ISDA
        /// Actual/Actual (ICMA) — actual days over the actual days in the coupon period × frequency.
        case actualActualICMA
        /// Actual/360 — actual days, 360-day year. Money-market convention.
        case actual360
        /// Actual/365 (Fixed) — actual days, 365-day year regardless of leap years.
        case actual365Fixed

        /// Human-readable name, safe for UI.
        public var displayName: String {
            switch self {
            case .thirty360: return "30/360"
            case .thirtyE360: return "30E/360"
            case .thirtyE360ISDA: return "30E/360 (ISDA)"
            case .actualActualICMA: return "Actual/Actual (ICMA)"
            case .actual360: return "Actual/360"
            case .actual365Fixed: return "Actual/365 (Fixed)"
            }
        }

        /// True for the conventions whose numerator counts 30-day months.
        public var isThirtyBasis: Bool {
            switch self {
            case .thirty360, .thirtyE360, .thirtyE360ISDA: return true
            case .actualActualICMA, .actual360, .actual365Fixed: return false
            }
        }
    }

    // MARK: - Dates

    /// A calendar date with no time, zone or locale attached.
    ///
    /// `Codable` because a saved tape stores the inputs of every solved problem and re-derives the
    /// result when reopened (see `par/plan_tape.md`). Decoding validates: a corrupt file yields a
    /// `DecodingError`, never a trap and never a February 31st.
    public struct YearMonthDay: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
        public let year: Int
        public let month: Int
        public let day: Int

        /// - Precondition: the components must form a real calendar date (1582-onward Gregorian).
        public init(_ year: Int, _ month: Int, _ day: Int) {
            precondition(month >= 1 && month <= 12, "month must be 1...12, got \(month)")
            precondition(
                day >= 1 && day <= DayCount.daysInMonth(year: year, month: month),
                "day \(day) is not a valid day of \(year)-\(month)"
            )
            self.year = year
            self.month = month
            self.day = day
        }

        /// Parse an ISO `yyyy-MM-dd` string. Returns nil for anything else.
        public init?(iso: String) {
            let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 3,
                  let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
                  m >= 1, m <= 12,
                  d >= 1, d <= DayCount.daysInMonth(year: y, month: m)
            else { return nil }
            self.init(y, m, d)
        }

        public static func < (a: YearMonthDay, b: YearMonthDay) -> Bool {
            (a.year, a.month, a.day) < (b.year, b.month, b.day)
        }

        private enum CodingKeys: String, CodingKey { case year, month, day }

        /// Decoding routes through validation and *throws* on an impossible date — persisted data is
        /// untrusted input, so the failure mode is an error the app can report, not a precondition trap.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let year = try container.decode(Int.self, forKey: .year)
            let month = try container.decode(Int.self, forKey: .month)
            let day = try container.decode(Int.self, forKey: .day)
            guard month >= 1, month <= 12 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .month, in: container, debugDescription: "month \(month) is not 1...12"
                )
            }
            guard day >= 1, day <= DayCount.daysInMonth(year: year, month: month) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .day, in: container,
                    debugDescription: "\(year)-\(month) has no day \(day)"
                )
            }
            self.init(year, month, day)
        }

        public var description: String {
            String(format: "%04d-%02d-%02d", year, month, day)
        }

        /// Days since 1970-01-01 (negative before). The single conversion everything else uses.
        public var serial: Int { DayCount.serial(self) }

        /// True when this is the last day of February in its year.
        public var isLastDayOfFebruary: Bool {
            month == 2 && day == DayCount.daysInMonth(year: year, month: 2)
        }

        /// True when this is the last day of its month.
        public var isLastDayOfMonth: Bool {
            day == DayCount.daysInMonth(year: year, month: month)
        }
    }

    // MARK: - Calendar primitives

    /// Proleptic Gregorian leap-year rule: divisible by 4, except centuries not divisible by 400.
    public static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    /// Days in a given month, honouring the leap-year rule for February.
    public static func daysInMonth(year: Int, month: Int) -> Int {
        precondition(month >= 1 && month <= 12, "month must be 1...12")
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        default: return isLeapYear(year) ? 29 : 28
        }
    }

    /// Days in a year: 365, or 366 in a leap year.
    public static func daysInYear(_ year: Int) -> Int { isLeapYear(year) ? 366 : 365 }

    /// Days from 1970-01-01 to `date` (Howard Hinnant's `days_from_civil`; exact in `Int`).
    public static func serial(_ date: YearMonthDay) -> Int {
        let y = date.month <= 2 ? date.year - 1 : date.year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400                                        // 0...399
        let mp = (date.month + 9) % 12                                 // March = 0
        let doy = (153 * mp + 2) / 5 + date.day - 1                    // 0...365
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy                // 0...146096
        return era * 146_097 + doe - 719_468
    }

    /// The inverse of `serial` (`civil_from_days`).
    public static func date(serial: Int) -> YearMonthDay {
        let z = serial + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097                                    // 0...146096
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)              // 0...365
        let mp = (5 * doy + 2) / 153                                   // 0...11, March = 0
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return YearMonthDay(m <= 2 ? y + 1 : y, m, d)
    }

    /// Actual calendar days between two dates, signed.
    public static func actualDays(from start: YearMonthDay, to end: YearMonthDay) -> Int {
        serial(end) - serial(start)
    }

    /// `date` shifted by a whole number of days.
    public static func date(_ date: YearMonthDay, byAdding days: Int) -> YearMonthDay {
        self.date(serial: serial(date) + days)
    }

    /// `date` shifted by whole months, clamping the day to the target month's length.
    ///
    /// MODEL CAVEAT: end-of-month is *clamped*, not preserved — Jan 31 + 1 month is Feb 28/29, and
    /// adding a further month gives Mar 28/29, not Mar 31. This matches how payment schedules are
    /// generated from a nominal day-of-month.
    public static func date(_ date: YearMonthDay, byAddingMonths months: Int) -> YearMonthDay {
        let zeroBased = date.year * 12 + (date.month - 1) + months
        let year = Int(floor(Double(zeroBased) / 12.0))
        let month = zeroBased - year * 12 + 1
        return YearMonthDay(year, month, min(date.day, daysInMonth(year: year, month: month)))
    }

    /// 0 = Sunday … 6 = Saturday.
    public static func weekdayIndex(_ date: YearMonthDay) -> Int {
        let s = serial(date)
        return ((s % 7) + 11) % 7   // 1970-01-01 was a Thursday (index 4)
    }

    // MARK: - Day counts

    /// The numerator of the day-count fraction, per convention.
    ///
    /// For the 30/360 family this is the `(Y2−Y1)·360 + (M2−M1)·30 + (D2−D1)` count with the
    /// convention's own D1/D2 substitutions; for the actual conventions it is simply the calendar
    /// days between the dates.
    ///
    /// - Parameter terminationDate: only consulted by `.thirtyE360ISDA`, whose §4.16(h) rule
    ///   substitutes 30 for an end date falling on the last day of February **unless** that date is
    ///   the termination date of the swap. Pass nil when there is none.
    public static func days(
        from start: YearMonthDay,
        to end: YearMonthDay,
        convention: Convention,
        terminationDate: YearMonthDay? = nil
    ) -> Int {
        switch convention {
        case .thirty360, .thirtyE360, .thirtyE360ISDA:
            let (d1, d2) = thirtyBasisDays(
                from: start, to: end, convention: convention, terminationDate: terminationDate
            )
            return (end.year - start.year) * 360 + (end.month - start.month) * 30 + (d2 - d1)
        case .actualActualICMA, .actual360, .actual365Fixed:
            return actualDays(from: start, to: end)
        }
    }

    /// The D1/D2 day substitutions a 30/360 variant applies — exposed because ISDA publishes them
    /// column by column, so the oracle can check the substitution and not merely the total.
    public static func thirtyBasisDays(
        from start: YearMonthDay,
        to end: YearMonthDay,
        convention: Convention,
        terminationDate: YearMonthDay? = nil
    ) -> (d1: Int, d2: Int) {
        precondition(convention.isThirtyBasis, "\(convention) is not a 30/360 convention")
        var d1 = start.day
        var d2 = end.day
        switch convention {
        case .thirty360:                                     // §4.16(f)
            if d1 == 31 { d1 = 30 }
            if d2 == 31 && (start.day == 30 || start.day == 31) { d2 = 30 }
        case .thirtyE360:                                    // §4.16(g)
            if d1 == 31 { d1 = 30 }
            if d2 == 31 { d2 = 30 }
        case .thirtyE360ISDA:                                // §4.16(h)
            if d1 == 31 || start.isLastDayOfFebruary { d1 = 30 }
            if d2 == 31 || (end.isLastDayOfFebruary && end != terminationDate) { d2 = 30 }
        default:
            break
        }
        return (d1, d2)
    }

    /// The day-count fraction: the numerator over the convention's denominator, in years.
    ///
    /// - Parameters:
    ///   - periodsPerYear: coupon frequency, used only by `.actualActualICMA`.
    ///   - periodEnd: the end of the coupon period `start` falls in — also `.actualActualICMA` only.
    ///     Defaults to `end`, which is correct when the fraction spans exactly one coupon period.
    public static func yearFraction(
        from start: YearMonthDay,
        to end: YearMonthDay,
        convention: Convention,
        periodsPerYear: Int = 2,
        periodStart: YearMonthDay? = nil,
        periodEnd: YearMonthDay? = nil,
        terminationDate: YearMonthDay? = nil
    ) -> Double {
        switch convention {
        case .thirty360, .thirtyE360, .thirtyE360ISDA:
            let n = days(from: start, to: end, convention: convention, terminationDate: terminationDate)
            return Double(n) / 360.0
        case .actual360:
            return Double(actualDays(from: start, to: end)) / 360.0
        case .actual365Fixed:
            return Double(actualDays(from: start, to: end)) / 365.0
        case .actualActualICMA:
            precondition(periodsPerYear > 0, "periodsPerYear must be > 0")
            let ps = periodStart ?? start
            let pe = periodEnd ?? end
            let periodDays = actualDays(from: ps, to: pe)
            precondition(periodDays > 0, "coupon period must be non-empty")
            return Double(actualDays(from: start, to: end))
                / (Double(periodDays) * Double(periodsPerYear))
        }
    }

    /// Accrual fraction of a single coupon period: elapsed days over period days, per convention.
    /// This is the `(s − r)/s` of Treasury's accrued-interest formulas when `convention` is actual.
    public static func accrualFraction(
        periodStart: YearMonthDay,
        settlement: YearMonthDay,
        periodEnd: YearMonthDay,
        convention: Convention = .actualActualICMA
    ) -> Double {
        let elapsed = days(from: periodStart, to: settlement, convention: convention)
        let total = days(from: periodStart, to: periodEnd, convention: convention)
        precondition(total > 0, "coupon period must be non-empty")
        return Double(elapsed) / Double(total)
    }
}
