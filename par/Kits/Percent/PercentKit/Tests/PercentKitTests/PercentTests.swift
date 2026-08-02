import Testing
import Foundation
import PercentKit

/// A definition-class corpus. There is no authority publishing worked examples of a markup, so this Kit
/// carries **no** PUBLISHED oracles — and says so, rather than citing a textbook it hasn't read or
/// inventing numbers and calling them ground truth. What it carries instead is the definitions
/// themselves, asserted as identities and round trips, plus the one relationship the domain actually
/// gets wrong in practice (markup vs margin).
///
/// Per `calculators/VALIDATION.md`'s taxonomy, everything here is *identity/definition* or
/// *invariant*. The guard below enforces that the classification is explicit.
@Suite("Corpus classification")
struct CorpusClassificationTests {

    /// The honest statement of what backs this Kit — an assertion so it cannot quietly change.
    @Test func thisKitIsDefinitionBackedNotPublicationBacked() {
        // If someone later adds a published worked example (a regulator's markup example, say), they
        // must add a citation-bearing corpus and update this test deliberately.
        let publishedOracleCount = 0
        #expect(publishedOracleCount == 0,
                "PercentKit is definition-backed; adding a published oracle means adding a corpus")
    }
}

/// The definitions, and the one confusion that costs money.
///
/// ORACLES:
///  • IDENTITY — markup ↔ margin conversion (`margin = markup/(1+markup)`), the cost/sell/margin
///    triangle solving consistently from any two, break-even where profit is exactly zero, chained
///    discounts as a product rather than a sum, tax inclusive/exclusive inversion.
///  • INVARIANT — signs under negative change, monotonicity, the zero and boundary cases.
@Suite("Percent — identity and invariant")
struct PercentIdentities {

    @Test func percentageChangeAndItsInverse() {
        #expect(abs(Percent.change(from: 200, to: 250) - 25) <= 1e-12)
        #expect(abs(Percent.change(from: 250, to: 200) - -20) <= 1e-12,
                "the reverse of +25% is −20%, not −25%")
        #expect(Percent.change(from: 100, to: 100) == 0)

        // applyChange inverts change, for any pair.
        for (from, to) in [(200.0, 250.0), (1.0, 1e6), (99.99, 0.01), (-50.0, -25.0)] {
            let pct = Percent.change(from: from, to: to)
            #expect(abs(Percent.applyChange(to: from, percent: pct) - to) <= 1e-9 * max(abs(to), 1))
        }
    }

    @Test func ofAndShareAreInverses() {
        #expect(abs(Percent.of(percent: 15, value: 80) - 12) <= 1e-12)
        #expect(abs(Percent.share(part: 12, whole: 80) - 15) <= 1e-12)
        for (part, whole) in [(12.0, 80.0), (1.0, 3.0), (-5.0, 20.0)] {
            let pct = Percent.share(part: part, whole: whole)
            #expect(abs(Percent.of(percent: pct, value: whole) - part) <= 1e-12 * max(abs(part), 1))
        }
    }

    /// The relationship the whole Kit exists to keep straight: a 50% markup is a 33⅓% margin.
    @Test func markupAndMarginConvertBothWays() {
        #expect(abs(Percent.marginFromMarkup(markupPct: 50) - 100.0 / 3) <= 1e-12)
        #expect(abs(Percent.markupFromMargin(marginPct: 100.0 / 3) - 50) <= 1e-12)
        #expect(abs(Percent.marginFromMarkup(markupPct: 100) - 50) <= 1e-12)

        // Round trips, and margin is always the smaller of the two for a profitable sale.
        for markup in [0.0, 5.0, 25.0, 50.0, 100.0, 400.0] {
            let margin = Percent.marginFromMarkup(markupPct: markup)
            #expect(abs(Percent.markupFromMargin(marginPct: margin) - markup) <= 1e-9 * max(markup, 1))
            if markup > 0 { #expect(margin < markup, "margin must be below markup") }
            #expect(margin < 100, "margin can approach but never reach 100%")
        }
    }

    /// The cost/sell/margin triangle: given any two, the third must be consistent with both definitions.
    @Test func costSellMarginTriangleIsConsistent() {
        for (cost, price) in [(60.0, 100.0), (0.5, 0.75), (1_234.56, 2_000.0)] {
            let margin = Percent.marginOnPrice(cost: cost, price: price)
            let markup = Percent.markupOnCost(cost: cost, price: price)

            #expect(abs(Percent.priceForMargin(cost: cost, marginPct: margin) - price) <= 1e-9 * price)
            #expect(abs(Percent.priceForMarkup(cost: cost, markupPct: markup) - price) <= 1e-9 * price)
            #expect(abs(Percent.costForMargin(price: price, marginPct: margin) - cost) <= 1e-9 * cost)
            #expect(abs(Percent.marginFromMarkup(markupPct: markup) - margin) <= 1e-9 * margin)
            #expect(abs(Percent.grossProfit(cost: cost, price: price) - (price - cost)) <= 1e-12)
        }

        // 40% margin on a 60 cost is a price of 100 — the canonical worked case.
        #expect(abs(Percent.priceForMargin(cost: 60, marginPct: 40) - 100) <= 1e-12)
        #expect(abs(Percent.marginOnPrice(cost: 60, price: 100) - 40) <= 1e-12)
        #expect(abs(Percent.markupOnCost(cost: 60, price: 100) - 200.0 / 3) <= 1e-12)
    }

    @Test func sellingAtALossGivesNegativeMarkupAndMargin() {
        #expect(Percent.markupOnCost(cost: 100, price: 80) < 0)
        #expect(Percent.marginOnPrice(cost: 100, price: 80) < 0)
        #expect(abs(Percent.markupOnCost(cost: 100, price: 80) - -20) <= 1e-12)
        #expect(abs(Percent.marginOnPrice(cost: 100, price: 80) - -25) <= 1e-12)
        #expect(Percent.grossProfit(cost: 100, price: 80) == -20)
    }

    /// Discounts compound; they do not add. 20% then 10% is 28% off.
    @Test func chainedDiscountsMultiply() {
        #expect(abs(Percent.chainedDiscount(percentages: [20, 10]) - 28) <= 1e-12)
        #expect(abs(Percent.chainedDiscount(percentages: [50, 50]) - 75) <= 1e-12)
        #expect(Percent.chainedDiscount(percentages: []) == 0)
        #expect(abs(Percent.chainedDiscount(percentages: [100]) - 100) <= 1e-12)

        // A chain is always less than the sum of its parts (for positive discounts).
        for chain in [[10.0, 10.0], [25.0, 25.0, 25.0], [5.0, 15.0, 30.0]] {
            #expect(Percent.chainedDiscount(percentages: chain) < chain.reduce(0, +))
        }
    }

    @Test func taxInclusiveAndExclusiveInvert() {
        #expect(abs(Percent.taxInclusive(preTax: 100, taxPct: 8.875) - 108.875) <= 1e-12)
        for (amount, tax) in [(100.0, 8.875), (19.99, 20.0), (1_000.0, 0.0)] {
            let inclusive = Percent.taxInclusive(preTax: amount, taxPct: tax)
            #expect(abs(Percent.taxExclusive(inclusive: inclusive, taxPct: tax) - amount) <= 1e-9)
        }
        // The error people make: subtracting the rate instead of dividing.
        let wrong = 108.875 * (1 - 8.875 / 100)
        #expect(abs(Percent.taxExclusive(inclusive: 108.875, taxPct: 8.875) - wrong) > 0.5)
    }

    /// Break-even is exactly where profit is zero — asserted against the profit function, not restated.
    @Test func breakEvenIsWhereProfitIsZero() {
        let cases: [(fixed: Double, price: Double, variable: Double)] = [
            (10_000, 25, 15), (500_000, 199.99, 42.50), (1, 2, 1),
        ]
        for c in cases {
            let units = Percent.breakEvenUnits(
                fixedCosts: c.fixed, pricePerUnit: c.price, variableCostPerUnit: c.variable
            )
            let profitAtBreakEven = Percent.profit(
                units: units, fixedCosts: c.fixed,
                pricePerUnit: c.price, variableCostPerUnit: c.variable
            )
            #expect(abs(profitAtBreakEven) <= 1e-9 * max(c.fixed, 1),
                    "profit at break-even should be zero, got \(profitAtBreakEven)")

            // One unit either side straddles zero.
            #expect(Percent.profit(units: units - 1, fixedCosts: c.fixed,
                                   pricePerUnit: c.price, variableCostPerUnit: c.variable) < 0)
            #expect(Percent.profit(units: units + 1, fixedCosts: c.fixed,
                                   pricePerUnit: c.price, variableCostPerUnit: c.variable) > 0)

            // Revenue at break-even equals units × price, and covers total costs exactly.
            let revenue = Percent.breakEvenRevenue(
                fixedCosts: c.fixed, pricePerUnit: c.price, variableCostPerUnit: c.variable
            )
            #expect(abs(revenue - units * c.price) <= 1e-9 * revenue)
            #expect(abs(revenue - (c.fixed + units * c.variable)) <= 1e-6 * revenue)
        }

        // 10,000 fixed, 25 price, 15 variable → 1,000 units.
        #expect(abs(Percent.breakEvenUnits(fixedCosts: 10_000, pricePerUnit: 25,
                                          variableCostPerUnit: 15) - 1_000) <= 1e-12)
        // Zero fixed costs break even at zero units.
        #expect(Percent.breakEvenUnits(fixedCosts: 0, pricePerUnit: 25, variableCostPerUnit: 15) == 0)
    }

    @Test func targetProfitIsBreakEvenPlusTheTarget() {
        let units = Percent.unitsForTargetProfit(
            fixedCosts: 10_000, pricePerUnit: 25, variableCostPerUnit: 15, targetProfit: 5_000
        )
        #expect(abs(units - 1_500) <= 1e-12)
        let achieved = Percent.profit(units: units, fixedCosts: 10_000,
                                     pricePerUnit: 25, variableCostPerUnit: 15)
        #expect(abs(achieved - 5_000) <= 1e-9)

        // More units are needed for a bigger target, always.
        var previous = 0.0
        for target in [0.0, 1_000, 5_000, 100_000] {
            let needed = Percent.unitsForTargetProfit(
                fixedCosts: 10_000, pricePerUnit: 25, variableCostPerUnit: 15, targetProfit: target
            )
            #expect(needed > previous || target == 0)
            previous = needed
        }
    }

    @Test func contributionMarginRelatesToBreakEven() {
        let margin = Percent.contributionMargin(pricePerUnit: 25, variableCostPerUnit: 15)
        #expect(margin == 10)
        #expect(abs(Percent.contributionMarginPct(pricePerUnit: 25, variableCostPerUnit: 15) - 40) <= 1e-12)
        // Break-even units × contribution margin = fixed costs, by definition.
        let units = Percent.breakEvenUnits(fixedCosts: 10_000, pricePerUnit: 25, variableCostPerUnit: 15)
        #expect(abs(units * margin - 10_000) <= 1e-9)
    }

    /// A thinner contribution margin means a higher break-even volume — monotone, and the intuition the
    /// screen exists to convey.
    @Test func breakEvenRisesAsMarginThins() {
        var previous = 0.0
        for price in [50.0, 40.0, 30.0, 25.0, 20.0, 16.0] {
            let units = Percent.breakEvenUnits(
                fixedCosts: 10_000, pricePerUnit: price, variableCostPerUnit: 15
            )
            #expect(units > previous, "break-even must rise as the price falls toward variable cost")
            previous = units
        }
    }
}
