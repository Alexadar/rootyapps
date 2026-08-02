import Foundation

/// Depreciation: straight line, declining balance with the crossover to straight line, sum of the years'
/// digits, and the MACRS schedules the IRS requires for US tax. Pure, stateless.
///
/// MODEL CAVEAT (MACRS is computed, not looked up): IRS Publication 946 Appendix A publishes percentage
/// tables, and this Kit reproduces them from the underlying rules — 200% or 150% declining balance
/// switching to straight line, under the applicable placed-in-service convention — rather than shipping
/// the tables as data. The tables are the *oracle*.
///
/// MODEL CAVEAT (the IRS tables carry their rounding forward): the published percentages are not a
/// rounding of the continuous schedule. Each year is rounded to two decimals (three for 20-year
/// property) and **the rounded figure is what reduces the running basis**, so the rounding compounds.
/// That carry is what produces the published alternations — 7-year 8.93 / 8.92 / 8.93, 10-year
/// …6.55 / 6.56 / 6.55 — and what makes every column total exactly 100.00%. Computing the continuous
/// schedule instead misses the published tables by up to 0.0064 percentage points, so
/// `Rounding.irsTable` is the default for MACRS and `.exact` is available for anyone who wants the
/// underlying mathematics. Measured in par/scratch/macrs.py.
public enum Depreciation {

    // MARK: - Model

    public enum Method: String, CaseIterable, Sendable, Codable {
        case straightLine
        /// Declining balance at a stated factor, with no switch.
        case decliningBalance
        /// Declining balance switching to straight line in the year that yields more — what MACRS does.
        case decliningBalanceWithCrossover
        case sumOfYearsDigits
        /// MACRS GDS: 200% declining balance for 3/5/7/10-year property, 150% for 15/20-year, both
        /// switching to straight line, under a placed-in-service convention.
        case macrsGDS

        public var displayName: String {
            switch self {
            case .straightLine: return "Straight line"
            case .decliningBalance: return "Declining balance"
            case .decliningBalanceWithCrossover: return "Declining balance with crossover"
            case .sumOfYearsDigits: return "Sum of the years' digits"
            case .macrsGDS: return "MACRS (GDS)"
            }
        }
    }

    /// When in the year the asset was placed in service — the first-year fraction, and the mirrored
    /// stub at the end of the schedule.
    public enum Convention: String, CaseIterable, Sendable, Codable {
        /// Half-year: everything is treated as placed in service mid-year. IRS Table A-1.
        case halfYear
        /// Mid-quarter, first quarter: 87.5% of the first year. IRS Table A-2.
        case midQuarterFirst
        /// Mid-quarter, second quarter: 62.5%. IRS Table A-3.
        case midQuarterSecond
        /// Mid-quarter, third quarter: 37.5%. IRS Table A-4.
        case midQuarterThird
        /// Mid-quarter, fourth quarter: 12.5%. IRS Table A-5.
        case midQuarterFourth

        /// The fraction of the first year the asset is treated as held.
        public var firstYearFraction: Double {
            switch self {
            case .halfYear: return 0.5
            case .midQuarterFirst: return 3.5 / 4
            case .midQuarterSecond: return 2.5 / 4
            case .midQuarterThird: return 1.5 / 4
            case .midQuarterFourth: return 0.5 / 4
            }
        }

        public var displayName: String {
            switch self {
            case .halfYear: return "Half-year"
            case .midQuarterFirst: return "Mid-quarter, 1st quarter"
            case .midQuarterSecond: return "Mid-quarter, 2nd quarter"
            case .midQuarterThird: return "Mid-quarter, 3rd quarter"
            case .midQuarterFourth: return "Mid-quarter, 4th quarter"
            }
        }
    }

    /// How the yearly percentages are rounded as the schedule is built.
    public enum Rounding: Equatable, Sendable, Codable {
        /// The continuous schedule, unrounded.
        case exact
        /// The IRS tables' own arithmetic: round each year to `decimals` places and carry the rounded
        /// figure into the next year's basis.
        case irsTable(decimals: Int)

        func round(_ x: Double) -> Double {
            switch self {
            case .exact:
                return x
            case .irsTable(let decimals):
                let scale = pow(10.0, Double(decimals))
                // Round half **up**, which is what the published tables do; Swift's `rounded()` is
                // half-away-from-zero, and these values are all positive, so it agrees.
                return (x * scale).rounded() / scale
            }
        }
    }

    /// One year of a schedule. Amounts are in the same currency as `cost`.
    public struct Year: Equatable, Sendable, Codable {
        /// 1-based year of the recovery period.
        public let year: Int
        public let depreciation: Double
        /// Book value at the end of the year.
        public let bookValue: Double
        /// Cumulative depreciation through the end of the year.
        public let accumulated: Double
    }

    /// An asset, as the schedule builder needs it.
    ///
    /// `Codable` for tape replay (`par/plan_tape.md`); decoding validates and throws.
    public struct Asset: Equatable, Sendable, Codable {
        public var cost: Double
        /// Estimated salvage value. MACRS ignores salvage entirely, by statute — `macrs` asserts it is
        /// zero rather than silently dropping a value the caller supplied.
        public var salvage: Double
        public var recoveryYears: Int
        /// Declining-balance factor: 2.0 for double declining, 1.5 for 150%. Ignored by the straight-line
        /// and sum-of-years-digits methods.
        public var factor: Double

        public init(cost: Double, salvage: Double = 0, recoveryYears: Int, factor: Double = 2.0) {
            precondition(cost > 0, "cost must be > 0")
            precondition(salvage >= 0, "salvage must be >= 0")
            precondition(salvage <= cost, "salvage cannot exceed cost")
            precondition(recoveryYears >= 1, "recovery period must be at least one year")
            precondition(factor > 0, "declining-balance factor must be > 0")
            self.cost = cost
            self.salvage = salvage
            self.recoveryYears = recoveryYears
            self.factor = factor
        }

        private enum CodingKeys: String, CodingKey { case cost, salvage, recoveryYears, factor }

        /// Decoding validates and throws — a persisted asset is untrusted input.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let cost = try c.decode(Double.self, forKey: .cost)
            let salvage = try c.decode(Double.self, forKey: .salvage)
            let recoveryYears = try c.decode(Int.self, forKey: .recoveryYears)
            let factor = try c.decode(Double.self, forKey: .factor)
            guard cost > 0, cost.isFinite else {
                throw DecodingError.dataCorruptedError(
                    forKey: .cost, in: c, debugDescription: "cost must be finite and > 0")
            }
            guard salvage >= 0, salvage <= cost else {
                throw DecodingError.dataCorruptedError(
                    forKey: .salvage, in: c, debugDescription: "salvage must be in 0...cost")
            }
            guard recoveryYears >= 1 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .recoveryYears, in: c, debugDescription: "must be >= 1")
            }
            guard factor > 0, factor.isFinite else {
                throw DecodingError.dataCorruptedError(
                    forKey: .factor, in: c, debugDescription: "factor must be finite and > 0")
            }
            self.init(cost: cost, salvage: salvage, recoveryYears: recoveryYears, factor: factor)
        }
    }

    // MARK: - Classical methods

    /// Straight line: `(cost − salvage)/n`, the same every year.
    public static func straightLine(_ asset: Asset) -> [Year] {
        let annual = (asset.cost - asset.salvage) / Double(asset.recoveryYears)
        return schedule(asset, yearly: { _, _ in annual })
    }

    /// Declining balance at `asset.factor`, with no switch to straight line.
    ///
    /// MODEL CAVEAT: pure declining balance **does not** fully depreciate an asset. Each year takes a
    /// fixed fraction of what is left, so the remaining basis decays geometrically and still has value
    /// at the end of the recovery period — for 200% over 5 years, 7.8% of the depreciable base is left
    /// unclaimed. That shortfall is precisely why the crossover method exists, and the Kit reports it
    /// honestly instead of quietly forcing the last year to close.
    /// Deductions are still floored at salvage: nothing depreciates below it.
    public static func decliningBalance(_ asset: Asset) -> [Year] {
        let rate = asset.factor / Double(asset.recoveryYears)
        return schedule(asset, yearly: { remainingBasis, _ in remainingBasis * rate })
    }

    /// Declining balance switching to straight line over the remaining life in the first year that
    /// straight line yields more — the method underneath MACRS.
    public static func decliningBalanceWithCrossover(_ asset: Asset) -> [Year] {
        let rate = asset.factor / Double(asset.recoveryYears)
        return schedule(asset, yearly: { remainingBasis, year in
            let remainingLife = Double(asset.recoveryYears - year + 1)
            let db = remainingBasis * rate
            let sl = remainingLife > 0 ? remainingBasis / remainingLife : remainingBasis
            return max(db, sl)
        })
    }

    /// The first year in which straight line beats declining balance, 1-based. Nil when it never does.
    public static func crossoverYear(_ asset: Asset) -> Int? {
        let rate = asset.factor / Double(asset.recoveryYears)
        var basis = asset.cost - asset.salvage
        for year in 1...asset.recoveryYears {
            let remainingLife = Double(asset.recoveryYears - year + 1)
            let db = basis * rate
            let sl = basis / remainingLife
            if sl > db { return year }
            basis -= db
        }
        return nil
    }

    /// Sum of the years' digits: year k gets `(n − k + 1)/(n(n+1)/2)` of the depreciable base.
    public static func sumOfYearsDigits(_ asset: Asset) -> [Year] {
        let n = Double(asset.recoveryYears)
        let denominator = n * (n + 1) / 2
        let base = asset.cost - asset.salvage
        return schedule(asset, yearly: { _, year in
            base * (n - Double(year) + 1) / denominator
        })
    }

    /// The sum-of-years-digits weight for one year — exposed because it is the definition, and the tests
    /// assert the schedule against it.
    public static func sumOfYearsDigitsFactor(year k: Int, recoveryYears n: Int) -> Double {
        precondition(k >= 1 && k <= n, "year out of range")
        return Double(n - k + 1) / (Double(n) * Double(n + 1) / 2)
    }

    // MARK: - MACRS

    /// The GDS declining-balance factor Publication 946 prescribes for a recovery period: 200% for
    /// 3-, 5-, 7- and 10-year property, 150% for 15- and 20-year.
    public static func macrsFactor(recoveryYears: Int) -> Double {
        switch recoveryYears {
        case 3, 5, 7, 10: return 2.0
        case 15, 20: return 1.5
        default: return 2.0
        }
    }

    /// The number of decimal places the published table for a recovery period carries: three for
    /// 20-year property, two for the rest.
    public static func macrsTableDecimals(recoveryYears: Int) -> Int {
        recoveryYears == 20 ? 3 : 2
    }

    /// The MACRS GDS recovery percentages, in percent of unadjusted basis, one per year.
    ///
    /// Reproduces IRS Publication 946 Appendix A. With `.irsTable` (the default) the rounding carries
    /// forward exactly as the published tables do; with `.exact` you get the underlying continuous
    /// schedule, which differs from the tables by up to 0.0064 pp.
    public static func macrsPercentages(
        recoveryYears: Int,
        convention: Convention = .halfYear,
        rounding: Rounding? = nil
    ) -> [Double] {
        precondition(recoveryYears >= 1, "recovery period must be at least one year")
        let factor = macrsFactor(recoveryYears: recoveryYears)
        let rounding = rounding ?? .irsTable(decimals: macrsTableDecimals(recoveryYears: recoveryYears))
        let rate = factor / Double(recoveryYears)

        var basis = 100.0
        var elapsed = 0.0
        var out: [Double] = []
        var year = 1
        while basis > 1e-12 && year <= recoveryYears + 1 {
            let fraction = year == 1
                ? convention.firstYearFraction
                : min(1.0, Double(recoveryYears) - elapsed)
            let remainingLife = Double(recoveryYears) - elapsed
            let db = basis * rate * fraction
            let sl = remainingLife > 0 ? (basis / remainingLife) * fraction : basis
            let deduction = rounding.round(min(max(db, sl), basis))
            out.append(deduction)
            basis -= deduction
            elapsed += fraction
            year += 1
        }
        return out
    }

    /// A MACRS schedule in money: `cost` times each published percentage.
    ///
    /// - Precondition: MACRS ignores salvage value by statute, so the asset's must be zero. Silently
    ///   dropping a salvage the caller supplied would produce a plausible, wrong deduction.
    public static func macrs(
        _ asset: Asset,
        convention: Convention = .halfYear,
        rounding: Rounding? = nil
    ) -> [Year] {
        precondition(asset.salvage == 0, "MACRS ignores salvage value; pass an asset with salvage 0")
        let percentages = macrsPercentages(
            recoveryYears: asset.recoveryYears, convention: convention, rounding: rounding
        )
        var accumulated = 0.0
        return percentages.enumerated().map { index, percent in
            let deduction = asset.cost * percent / 100
            accumulated += deduction
            return Year(year: index + 1, depreciation: deduction,
                        bookValue: asset.cost - accumulated, accumulated: accumulated)
        }
    }

    // MARK: - Shared schedule builder

    /// Walks a schedule from a per-year rule, clipping the last deduction so book value lands exactly on
    /// salvage — no method may depreciate past it.
    private static func schedule(
        _ asset: Asset, yearly: (_ remainingBasis: Double, _ year: Int) -> Double
    ) -> [Year] {
        var basis = asset.cost - asset.salvage
        var accumulated = 0.0
        var out: [Year] = []
        out.reserveCapacity(asset.recoveryYears)

        for year in 1...asset.recoveryYears {
            var deduction = yearly(basis, year)
            deduction = min(max(deduction, 0), basis)
            basis -= deduction
            accumulated += deduction
            out.append(Year(year: year, depreciation: deduction,
                            bookValue: asset.cost - accumulated, accumulated: accumulated))
        }
        return out
    }

    /// Book value at the end of a given year under a chosen method.
    public static func bookValue(
        _ asset: Asset, method: Method, afterYear year: Int,
        convention: Convention = .halfYear
    ) -> Double {
        precondition(year >= 0, "year must be >= 0")
        if year == 0 { return asset.cost }
        let rows = schedule(asset, method: method, convention: convention)
        guard year <= rows.count else { return rows.last?.bookValue ?? asset.cost }
        return rows[year - 1].bookValue
    }

    /// The schedule for a chosen method — the single entry point a UI needs.
    public static func schedule(
        _ asset: Asset, method: Method, convention: Convention = .halfYear
    ) -> [Year] {
        switch method {
        case .straightLine: return straightLine(asset)
        case .decliningBalance: return decliningBalance(asset)
        case .decliningBalanceWithCrossover: return decliningBalanceWithCrossover(asset)
        case .sumOfYearsDigits: return sumOfYearsDigits(asset)
        case .macrsGDS: return macrs(asset, convention: convention)
        }
    }
}
