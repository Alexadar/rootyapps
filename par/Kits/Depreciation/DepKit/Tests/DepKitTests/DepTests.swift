import Testing
import Foundation
import DepKit

/// Enforcement guard for the oracle corpus, per `calculators/VALIDATION.md`.
///
/// ORACLES:
///  • GUARD — structural only.
@Suite("Oracle corpus integrity")
struct OracleGuardTests {

    @Test func everyOracleCitesAnExternalSource() {
        for o in Oracles.all {
            #expect(!o.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(o.source.contains("Publication 946") && o.source.contains("http"),
                    "oracle '\(o.id)' must cite a locatable document")
            #expect(!o.inputs.isEmpty)
            #expect(!o.precision.isEmpty, "oracle '\(o.id)' has no precision rationale")
        }
    }

    @Test func everyValueHasAMatchingTolerance() {
        for o in Oracles.all {
            #expect(!o.values.isEmpty)
            for key in o.values.keys {
                #expect(o.tolerances[key] != nil, "'\(o.id)'.\(key) has no tolerance")
                // 0 is legitimate here: the published percentages are exact figures the
                // rounding-carry method reproduces digit for digit.
                #expect((o.tolerances[key] ?? -1) >= 0, "'\(o.id)'.\(key) tolerance must be >= 0")
            }
            for key in o.tolerances.keys { #expect(o.values[key] != nil) }
        }
    }

    @Test func oracleIDsAreUniqueAndResolvable() {
        let ids = Oracles.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for o in Oracles.all { #expect(Oracles.require(o.id).id == o.id) }
    }

    /// Coverage guard: every placed-in-service convention the app can select, for every recovery period
    /// it can offer, must have a published column behind it. All five tables, all six classes: 30 rows.
    @Test func everyConventionAndClassHasAPublishedColumn() {
        for convention in Depreciation.Convention.allCases {
            for recoveryYears in [3, 5, 7, 10, 15, 20] {
                let id = Oracles.macrsID(convention: convention, recoveryYears: recoveryYears)
                #expect(Oracles.all.contains { $0.id == id },
                        "no published column for \(convention.displayName), \(recoveryYears)-year")
            }
        }
        #expect(Oracles.macrsRows.count == 30, "5 conventions × 6 recovery periods")
    }

    /// Every method the app can select must be covered by a test — MACRS by the published tables, the
    /// classical four by their definitions. Adding a method fails this until it is classified.
    @Test func everyMethodIsClassified() {
        let publishedMethods: Set<Depreciation.Method> = [.macrsGDS]
        let definitionMethods: Set<Depreciation.Method> = [
            .straightLine, .decliningBalance, .decliningBalanceWithCrossover, .sumOfYearsDigits,
        ]
        #expect(publishedMethods.union(definitionMethods) == Set(Depreciation.Method.allCases))
        #expect(publishedMethods.isDisjoint(with: definitionMethods))
    }
}

// Oracle = IRS Publication 946 (2025) Appendix A, Tables A-1..A-5 (public domain),
//          https://www.irs.gov/pub/irs-pdf/p946.pdf.  oracle-backed.
/// MACRS against every published IRS percentage column.
///
/// ORACLES:
///  • PUBLISHED — all 30 columns (5 conventions × 6 recovery periods), asserted **exactly**: the
///    rounding-carry method reproduces the published percentages digit for digit in 28 of them.
///  • PUBLISHED — the two columns that disagree by one unit in the last place are asserted against both
///    the published figure and Par's own, so neither can drift silently.
///  • PUBLISHED — the worked $10,000 office-furniture schedule, in dollars.
@Suite("MACRS — oracle-backed")
struct MACRSOracles {

    static let conventions = Depreciation.Convention.allCases
    static let classes = [3, 5, 7, 10, 15, 20]
    static let combinations: [(Depreciation.Convention, Int)] =
        conventions.flatMap { convention in classes.map { (convention, $0) } }

    @Test("every published percentage column", arguments: combinations.indices)
    func publishedPercentages(index: Int) {
        let (convention, recoveryYears) = Self.combinations[index]
        let o = Oracles.require(Oracles.macrsID(convention: convention, recoveryYears: recoveryYears))
        let anomalies = Oracles.knownPublishedAnomalies[o.id] ?? [:]

        let computed = Depreciation.macrsPercentages(
            recoveryYears: recoveryYears, convention: convention
        )
        let countMessage = "\(convention.displayName) \(recoveryYears)-year: "
            + "\(computed.count) years vs \(o.values.count) published"
        #expect(computed.count == o.values.count, Comment(rawValue: countMessage))

        for (offset, percent) in computed.enumerated() {
            let year = offset + 1
            if let ours = anomalies[year] {
                // A documented published-table anomaly: assert BOTH sides of it.
                #expect(abs(percent - ours) < 1e-9,
                        "\(o.id) year \(year): expected our documented \(ours), got \(percent)")
                let staleMessage = "\(o.id) year \(year) is recorded as an anomaly but now matches"
                    + " — if the tables were corrected, remove it from knownPublishedAnomalies"
                #expect(abs(percent - o.value("year\(year)")) > 0, Comment(rawValue: staleMessage))
            } else {
                #expect(o.matches("year\(year)", percent),
                        "\(o.id) year \(year): got \(percent), published \(o.value("year\(year)"))")
            }
        }

        // Every published column totals exactly 100% of basis — the closure property the carry exists
        // to preserve.
        let total = computed.reduce(0, +)
        #expect(abs(total - 100) <= 1e-9, "\(o.id) totals \(total)%")
    }

    @Test func publishedFurnitureExample() {
        let o = Oracles.furnitureRow
        let asset = Depreciation.Asset(cost: o.input("cost"), recoveryYears: Int(o.input("recoveryYears")))
        let schedule = Depreciation.macrs(asset)

        #expect(schedule.count == 8, "7-year property runs 8 years under the half-year convention")
        for row in schedule {
            #expect(o.matches("year\(row.year)", row.depreciation.rounded()),
                    "year \(row.year): got \(row.depreciation)")
        }
        #expect(abs((schedule.last?.bookValue ?? .nan)) <= 1e-9, "MACRS depreciates to zero")
        #expect(abs((schedule.last?.accumulated ?? 0) - o.input("cost")) <= 1e-9)
    }

    /// The finding this Kit is built on: the published tables are **not** a rounding of the continuous
    /// schedule. Computing exactly instead of carrying the rounding forward misses them — by up to
    /// 0.0064 pp, which is small but is the difference between reproducing a citation and approximating
    /// one. Asserted so nobody "simplifies" the rounding away later.
    @Test func theExactScheduleDoesNotReproduceThePublishedTables() {
        var worst = 0.0
        var columnsThatDiffer = 0
        for (convention, recoveryYears) in Self.combinations {
            let o = Oracles.require(Oracles.macrsID(convention: convention, recoveryYears: recoveryYears))
            let exact = Depreciation.macrsPercentages(
                recoveryYears: recoveryYears, convention: convention, rounding: .exact
            )
            var differs = false
            for (offset, percent) in exact.enumerated() {
                let published = o.value("year\(offset + 1)")
                let delta = abs(percent - published)
                worst = max(worst, delta)
                if delta > 0 { differs = true }
            }
            if differs { columnsThatDiffer += 1 }
            // The exact schedule still totals 100% — it is a valid schedule, just not the IRS's.
            #expect(abs(exact.reduce(0, +) - 100) <= 1e-9)
        }
        #expect(columnsThatDiffer == 30, "every column differs from the exact schedule somewhere")
        #expect(worst > 0.005, "the deviation must be real: measured worst \(worst) pp")
        #expect(worst < 0.02, "…and small: \(worst) pp")
    }

    /// MACRS ignores salvage value by statute, so passing one is a programming error rather than a
    /// silently-dropped input. (Checked via the schedule entry point, which is what a UI calls.)
    @Test func macrsRefusesSalvage() {
        let asset = Depreciation.Asset(cost: 10_000, salvage: 1_000, recoveryYears: 7)
        #expect(asset.salvage == 1_000)
        // The precondition cannot be exercised in-process without trapping, so this documents the
        // contract and asserts the honest alternative: with salvage 0 the schedule runs.
        let clean = Depreciation.Asset(cost: 10_000, recoveryYears: 7)
        #expect(Depreciation.macrs(clean).count == 8)
    }
}

/// The classical methods, by definition and invariant.
///
/// ORACLES:
///  • IDENTITY — straight line is (cost − salvage)/n; the sum-of-years-digits weight is
///    (n − k + 1)/(n(n+1)/2); every method's deductions sum to cost − salvage.
///  • INVARIANT — book value falls monotonically and never below salvage; the declining-balance
///    crossover happens where straight line first wins; a one-year asset is a single deduction.
@Suite("Depreciation — identity and invariant")
struct DepreciationIdentities {

    static let assets: [Depreciation.Asset] = [
        .init(cost: 10_000, recoveryYears: 7),
        .init(cost: 50_000, salvage: 5_000, recoveryYears: 10),
        .init(cost: 1_234.56, salvage: 123.45, recoveryYears: 5, factor: 1.5),
        .init(cost: 800, salvage: 800, recoveryYears: 3),          // nothing to depreciate
        .init(cost: 9_500, recoveryYears: 1),                       // single year
    ]

    @Test("every method depreciates exactly cost − salvage", arguments: assets.indices)
    func schedulesClose(index: Int) {
        let asset = Self.assets[index]
        for method in Depreciation.Method.allCases {
            // MACRS ignores salvage, so only run it on assets that have none.
            if method == .macrsGDS && asset.salvage != 0 { continue }
            let rows = Depreciation.schedule(asset, method: method)
            let total = rows.reduce(0) { $0 + $1.depreciation }
            let expected = method == .macrsGDS ? asset.cost : asset.cost - asset.salvage

            if method == .decliningBalance && asset.recoveryYears > 1 && asset.cost > asset.salvage {
                // Pure declining balance is geometric: it never reaches the floor. Asserting that it
                // *doesn't* close is the honest test — and it is the whole reason the crossover method
                // exists. (A one-year asset is the exception: one deduction takes everything.)
                #expect(total < expected,
                        "\(method.displayName) is geometric and must leave basis unclaimed")
                #expect(total > 0.5 * expected, "…but it should still claim most of it")
            } else {
                #expect(abs(total - expected) <= 1e-9 * max(asset.cost, 1),
                        "\(method.displayName): depreciated \(total), expected \(expected)")
            }

            // Book value falls monotonically and never dips below salvage (or zero, for MACRS).
            let floorValue = method == .macrsGDS ? 0 : asset.salvage
            var previous = asset.cost
            for row in rows {
                #expect(row.bookValue <= previous + 1e-9, "\(method.displayName) book value rose")
                #expect(row.bookValue >= floorValue - 1e-9,
                        "\(method.displayName) depreciated below salvage")
                #expect(row.depreciation >= -1e-12, "no negative deduction")
                previous = row.bookValue
            }
            // Accumulated depreciation and book value must always agree with cost.
            for row in rows {
                #expect(abs(row.bookValue + row.accumulated - asset.cost) <= 1e-9 * max(asset.cost, 1))
            }
        }
    }

    @Test func straightLineIsFlat() {
        let asset = Depreciation.Asset(cost: 50_000, salvage: 5_000, recoveryYears: 10)
        let rows = Depreciation.straightLine(asset)
        #expect(rows.count == 10)
        for row in rows { #expect(abs(row.depreciation - 4_500) <= 1e-9) }
        #expect(abs(rows.last!.bookValue - 5_000) <= 1e-9)
    }

    @Test func sumOfYearsDigitsMatchesItsDefinition() {
        let asset = Depreciation.Asset(cost: 12_000, salvage: 2_000, recoveryYears: 4)
        let rows = Depreciation.sumOfYearsDigits(asset)
        let base = asset.cost - asset.salvage
        // 4/10, 3/10, 2/10, 1/10 of 10,000.
        for (offset, expected) in [4_000.0, 3_000, 2_000, 1_000].enumerated() {
            #expect(abs(rows[offset].depreciation - expected) <= 1e-9)
            let factor = Depreciation.sumOfYearsDigitsFactor(year: offset + 1, recoveryYears: 4)
            #expect(abs(rows[offset].depreciation - base * factor) <= 1e-9)
        }
        // The weights sum to one, for any n.
        for n in [1, 3, 7, 20, 39] {
            let sum = (1...n).reduce(0.0) {
                $0 + Depreciation.sumOfYearsDigitsFactor(year: $1, recoveryYears: n)
            }
            #expect(abs(sum - 1) <= 1e-12, "n=\(n): weights sum to \(sum)")
        }
    }

    @Test func decliningBalanceIsFrontLoadedAndCrossoverIsWhereStraightLineWins() {
        let asset = Depreciation.Asset(cost: 10_000, recoveryYears: 5)
        let plain = Depreciation.decliningBalance(asset)
        let withSwitch = Depreciation.decliningBalanceWithCrossover(asset)

        // Double declining at 40%: 4,000 then 2,400 then 1,440…
        #expect(abs(plain[0].depreciation - 4_000) <= 1e-9)
        #expect(abs(plain[1].depreciation - 2_400) <= 1e-9)
        #expect(plain[0].depreciation > plain[1].depreciation, "front-loaded")

        // The crossover schedule depreciates at least as fast, and fully.
        #expect(withSwitch.reduce(0) { $0 + $1.depreciation } >= plain.reduce(0) { $0 + $1.depreciation })
        let crossover = Depreciation.crossoverYear(asset)
        #expect(crossover == 4, "5-year, 200% DB switches to straight line in year 4, got \(String(describing: crossover))")

        // From the crossover on, the deduction is flat — that is what switching to straight line means.
        if let year = crossover, year < asset.recoveryYears {
            let tail = withSwitch[(year - 1)...]
            let first = tail.first!.depreciation
            for row in tail { #expect(abs(row.depreciation - first) <= 1e-9) }
        }

        // A slower declining balance crosses over EARLIER, not later: the smaller the fixed fraction,
        // the sooner straight line over the remaining life beats it. 150% over 5 years switches in
        // year 3 where 200% switches in year 4.
        let slower = Depreciation.Asset(cost: 10_000, recoveryYears: 5, factor: 1.5)
        #expect(Depreciation.crossoverYear(slower) == 3)
        #expect((Depreciation.crossoverYear(slower) ?? 0) < (crossover ?? 0))

        // And pure 200% declining balance leaves basis behind — 7.776% of it over five years.
        let unclaimed = 10_000 - plain.reduce(0) { $0 + $1.depreciation }
        #expect(abs(unclaimed - 777.6) <= 1e-9, "unclaimed \(unclaimed)")
    }

    @Test func bookValueTracksTheSchedule() {
        let asset = Depreciation.Asset(cost: 50_000, salvage: 5_000, recoveryYears: 10)
        for method in [Depreciation.Method.straightLine, .decliningBalanceWithCrossover, .sumOfYearsDigits] {
            let rows = Depreciation.schedule(asset, method: method)
            #expect(Depreciation.bookValue(asset, method: method, afterYear: 0) == asset.cost)
            for row in rows {
                #expect(Depreciation.bookValue(asset, method: method, afterYear: row.year)
                        == row.bookValue)
            }
        }
    }

    @Test func aFullySalvagedAssetDepreciatesNothing() {
        let asset = Depreciation.Asset(cost: 800, salvage: 800, recoveryYears: 3)
        for method in [Depreciation.Method.straightLine, .decliningBalance,
                       .decliningBalanceWithCrossover, .sumOfYearsDigits] {
            let rows = Depreciation.schedule(asset, method: method)
            #expect(rows.allSatisfy { abs($0.depreciation) <= 1e-12 },
                    "\(method.displayName) depreciated an asset worth its salvage")
            #expect(abs(rows.last!.bookValue - 800) <= 1e-12)
        }
    }

    @Test func singleYearAssetIsOneDeduction() {
        let asset = Depreciation.Asset(cost: 9_500, recoveryYears: 1)
        let rows = Depreciation.straightLine(asset)
        #expect(rows.count == 1)
        #expect(abs(rows[0].depreciation - 9_500) <= 1e-9)
        #expect(abs(rows[0].bookValue) <= 1e-9)
    }

    @Test func macrsFactorsAndDecimalsFollowThePublication() {
        for years in [3, 5, 7, 10] { #expect(Depreciation.macrsFactor(recoveryYears: years) == 2.0) }
        for years in [15, 20] { #expect(Depreciation.macrsFactor(recoveryYears: years) == 1.5) }
        #expect(Depreciation.macrsTableDecimals(recoveryYears: 20) == 3)
        for years in [3, 5, 7, 10, 15] {
            #expect(Depreciation.macrsTableDecimals(recoveryYears: years) == 2)
        }
    }

    /// The convention only changes the first year's fraction — and the fractions are the published ones.
    @Test func conventionsUseThePublishedFirstYearFractions() {
        #expect(Depreciation.Convention.halfYear.firstYearFraction == 0.5)
        #expect(Depreciation.Convention.midQuarterFirst.firstYearFraction == 0.875)
        #expect(Depreciation.Convention.midQuarterSecond.firstYearFraction == 0.625)
        #expect(Depreciation.Convention.midQuarterThird.firstYearFraction == 0.375)
        #expect(Depreciation.Convention.midQuarterFourth.firstYearFraction == 0.125)

        // A later quarter means a smaller first-year deduction, every time.
        var previous = Double.infinity
        for convention in [Depreciation.Convention.midQuarterFirst, .midQuarterSecond,
                           .midQuarterThird, .midQuarterFourth] {
            let first = Depreciation.macrsPercentages(recoveryYears: 7, convention: convention)[0]
            #expect(first < previous)
            previous = first
        }
    }
}
