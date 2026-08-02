import Foundation

/// Business percentages: change, markup, margin, break-even and the cost/sell/margin triangle.
/// Pure, stateless.
///
/// MODEL CAVEAT (markup is not margin): markup is stated on **cost**, margin on **price**. A 50% markup
/// is a 33⅓% margin. Confusing the two is the most expensive arithmetic error in retail, and it is why
/// this Kit names them separately and converts between them explicitly rather than offering one
/// "percent" function.
///
/// These are definitions, not conventions — there is no regulator publishing worked examples of a
/// markup — so the tests assert them as identities and round trips, and the corpus says so plainly
/// rather than dressing a definition up as a citation.
public enum Percent {

    // MARK: - Change and share

    /// Percentage change from `from` to `to`: `100·(to − from)/from`.
    ///
    /// - Precondition: `from` must be non-zero. There is no percentage change from nothing, and
    ///   returning infinity or zero would both be lies.
    public static func change(from: Double, to: Double) -> Double {
        precondition(from != 0, "percentage change from zero is undefined")
        return 100 * (to - from) / from
    }

    /// The value after applying a percentage change.
    public static func applyChange(to value: Double, percent: Double) -> Double {
        value * (1 + percent / 100)
    }

    /// `percent` of `value`.
    public static func of(percent: Double, value: Double) -> Double {
        value * percent / 100
    }

    /// What percentage `part` is of `whole`: `100·part/whole`.
    public static func share(part: Double, whole: Double) -> Double {
        precondition(whole != 0, "share of zero is undefined")
        return 100 * part / whole
    }

    /// Several successive discounts, which do **not** add up: 20% then 10% off is 28% off, not 30%.
    public static func chainedDiscount(percentages: [Double]) -> Double {
        let remaining = percentages.reduce(1.0) { $0 * (1 - $1 / 100) }
        return 100 * (1 - remaining)
    }

    // MARK: - Markup, margin and the cost/sell/margin triangle

    /// Markup on cost, as a percentage: `100·(price − cost)/cost`.
    public static func markupOnCost(cost: Double, price: Double) -> Double {
        precondition(cost != 0, "markup on a zero cost is undefined")
        return 100 * (price - cost) / cost
    }

    /// Gross margin on price, as a percentage: `100·(price − cost)/price`.
    public static func marginOnPrice(cost: Double, price: Double) -> Double {
        precondition(price != 0, "margin on a zero price is undefined")
        return 100 * (price - cost) / price
    }

    /// Convert a markup on cost to the equivalent margin on price: `markup/(1 + markup)`.
    public static func marginFromMarkup(markupPct: Double) -> Double {
        let m = markupPct / 100
        precondition(m > -1, "a markup of -100% or worse has no margin")
        return 100 * m / (1 + m)
    }

    /// Convert a margin on price to the equivalent markup on cost: `margin/(1 − margin)`.
    public static func markupFromMargin(marginPct: Double) -> Double {
        let m = marginPct / 100
        precondition(m < 1, "a 100% margin implies an infinite markup")
        return 100 * m / (1 - m)
    }

    /// The selling price that achieves a target margin on price.
    public static func priceForMargin(cost: Double, marginPct: Double) -> Double {
        precondition(marginPct < 100, "a 100% margin is unreachable at any finite price")
        return cost / (1 - marginPct / 100)
    }

    /// The selling price that achieves a target markup on cost.
    public static func priceForMarkup(cost: Double, markupPct: Double) -> Double {
        cost * (1 + markupPct / 100)
    }

    /// The cost that leaves a target margin at a given price.
    public static func costForMargin(price: Double, marginPct: Double) -> Double {
        price * (1 - marginPct / 100)
    }

    /// Gross profit in money.
    public static func grossProfit(cost: Double, price: Double) -> Double { price - cost }

    // MARK: - Tax

    /// Add tax to a pre-tax amount.
    public static func taxInclusive(preTax: Double, taxPct: Double) -> Double {
        preTax * (1 + taxPct / 100)
    }

    /// Recover the pre-tax amount from a tax-inclusive total — the calculation people get wrong by
    /// subtracting the tax percentage instead of dividing.
    public static func taxExclusive(inclusive: Double, taxPct: Double) -> Double {
        precondition(taxPct > -100, "tax of -100% or worse is undefined")
        return inclusive / (1 + taxPct / 100)
    }

    // MARK: - Break-even

    /// Units that must sell to cover fixed costs: `fixed/(price − variable)`.
    ///
    /// - Precondition: the contribution margin `price − variable` must be positive. A product sold below
    ///   its variable cost has no break-even volume, and returning a negative one would be nonsense
    ///   dressed as an answer.
    public static func breakEvenUnits(fixedCosts: Double, pricePerUnit: Double, variableCostPerUnit: Double)
        -> Double
    {
        let contribution = pricePerUnit - variableCostPerUnit
        precondition(contribution > 0, "price must exceed variable cost to break even")
        precondition(fixedCosts >= 0, "fixed costs must be >= 0")
        return fixedCosts / contribution
    }

    /// Revenue at the break-even volume.
    public static func breakEvenRevenue(
        fixedCosts: Double, pricePerUnit: Double, variableCostPerUnit: Double
    ) -> Double {
        breakEvenUnits(
            fixedCosts: fixedCosts, pricePerUnit: pricePerUnit, variableCostPerUnit: variableCostPerUnit
        ) * pricePerUnit
    }

    /// Units needed to reach a target profit — break-even with the target added to fixed costs.
    public static func unitsForTargetProfit(
        fixedCosts: Double, pricePerUnit: Double, variableCostPerUnit: Double, targetProfit: Double
    ) -> Double {
        breakEvenUnits(
            fixedCosts: fixedCosts + targetProfit,
            pricePerUnit: pricePerUnit,
            variableCostPerUnit: variableCostPerUnit
        )
    }

    /// Contribution margin per unit, in money.
    public static func contributionMargin(pricePerUnit: Double, variableCostPerUnit: Double) -> Double {
        pricePerUnit - variableCostPerUnit
    }

    /// Contribution margin as a percentage of price.
    public static func contributionMarginPct(pricePerUnit: Double, variableCostPerUnit: Double) -> Double {
        precondition(pricePerUnit != 0, "contribution margin on a zero price is undefined")
        return 100 * (pricePerUnit - variableCostPerUnit) / pricePerUnit
    }

    /// Profit at a given volume.
    public static func profit(
        units: Double, fixedCosts: Double, pricePerUnit: Double, variableCostPerUnit: Double
    ) -> Double {
        units * (pricePerUnit - variableCostPerUnit) - fixedCosts
    }
}
