import Foundation
import SwiftUI
import PercentKit

/// Markup versus margin, and break-even. Two questions that get answered wrongly in the same two
/// ways every time: markup mistaken for margin, and discounts added instead of compounded.
@MainActor
public final class PercentViewModel: ObservableObject {

    public enum Mode: String, CaseIterable, Hashable {
        case margin = "Cost / Sell"
        case change = "Change"
        case breakEven = "Break-even"
    }

    @Published public var mode: Mode = .margin
    @Published public var cost: Double = 60
    @Published public var price: Double = 100
    @Published public var fixedCosts: Double = 10_000
    @Published public var variableCostPerUnit: Double = 15
    @Published public var targetProfit: Double = 0
    @Published public var rowLabel: String = ""

    public init() {}

    public static let moneyRange: ClosedRange<Double> = 0.01...1_000_000_000
    public static let fixedRange: ClosedRange<Double> = 0...1_000_000_000
    public static let profitRange: ClosedRange<Double> = 0...1_000_000_000

    // MARK: - Cost / sell / margin

    public var margin: Double { Percent.marginOnPrice(cost: cost, price: max(price, 0.01)) }
    public var markup: Double { Percent.markupOnCost(cost: max(cost, 0.01), price: price) }
    public var grossProfit: Double { Percent.grossProfit(cost: cost, price: price) }

    // MARK: - Percent change
    //
    // `Percent.change`, `applyChange`, `of`, `share`, `chainedDiscount`, `taxInclusive` and
    // `taxExclusive` were all written and oracle-tested, and no screen reached any of them. Percent
    // change is the single most reached-for function on a calculator like this — a rent review, a
    // year-on-year line, a bid against a mid.
    //
    // The two values reuse `cost` and `price` as *from* and *to* so the persisted row keeps exactly
    // the six scalars it already had; `mode` is what says how to read them.
    public var percentChange: Double { Percent.change(from: cost, to: price) }
    public var absoluteChange: Double { price - cost }
    /// The reverse question, always visible beside it: what `from` grows to at the same rate again.
    public var compoundedOnce: Double { Percent.applyChange(to: price, percent: percentChange) }

    // MARK: - Break-even

    public var contributionMargin: Double {
        Percent.contributionMargin(pricePerUnit: price, variableCostPerUnit: variableCostPerUnit)
    }

    public var contributionMarginPct: Double {
        Percent.contributionMarginPct(pricePerUnit: max(price, 0.01),
                                      variableCostPerUnit: variableCostPerUnit)
    }

    /// The Kit requires a positive contribution margin — a product sold below its variable cost has
    /// no break-even volume, and returning a negative one would be nonsense dressed as an answer.
    public var canBreakEven: Bool { price > variableCostPerUnit }

    public enum Outcome: Equatable {
        case solved(Double)
        case failed(String)
    }

    public var outcome: Outcome {
        switch mode {
        case .margin:
            guard price > 0 else { return .failed("A margin needs a selling price.") }
            return .solved(margin)
        case .change:
            // `Percent.change` traps on a zero base — a change from nothing is undefined, not
            // infinite.
            guard cost != 0 else { return .failed("A percent change needs a non-zero starting value.") }
            return .solved(percentChange)
        case .breakEven:
            guard canBreakEven else {
                return .failed("The price must exceed the variable cost, or no volume breaks even.")
            }
            return .solved(Percent.unitsForTargetProfit(
                fixedCosts: fixedCosts, pricePerUnit: price,
                variableCostPerUnit: variableCostPerUnit, targetProfit: targetProfit
            ))
        }
    }

    public var breakEvenRevenue: Double {
        guard canBreakEven else { return 0 }
        return Percent.breakEvenRevenue(fixedCosts: fixedCosts, pricePerUnit: price,
                                        variableCostPerUnit: variableCostPerUnit)
    }

    public var heroCaption: String {
        switch mode {
        case .margin: return "gross margin on price"
        case .change: return "change from the first value to the second"
        case .breakEven: return "units to reach the target"
        }
    }

    public var heroFootnote: String {
        switch mode {
        case .margin: return "markup on cost is \(Fmt.percent(markup, digits: 2))"
        case .change: return "\(Fmt.money(absoluteChange)) absolute · again would reach \(Fmt.money(compoundedOnce))"
        case .breakEven: return "at \(Fmt.money(contributionMargin)) contribution per unit"
        }
    }

    public var authorities: [String] { ["definition"] }

    public var conventions: [String] {
        switch mode {
        case .margin:
            return ["margin is on price", "markup is on cost", "the two are not interchangeable"]
        case .change:
            return ["change is on the first value", "a fall and the rise back are not equal"]
        case .breakEven:
            return ["fixed costs recovered first", "no variable cost step"]
        }
    }

    /// What the tape stores in `PercentInputs.mode`. Kept as plain strings rather than the raw
    /// values, because the raw values are user-facing titles and would take the file format with
    /// them if the titles ever changed.
    public func tapeRow() -> TapeRow? {
        guard case .solved = outcome else { return nil }
        return TapeRow(label: rowLabel, inputs: .percent(PercentInputs(
            mode: mode.storedName,
            cost: cost, price: price, fixedCosts: fixedCosts,
            variableCostPerUnit: variableCostPerUnit, targetProfit: targetProfit
        )))
    }
}

extension PercentViewModel.Mode {
    /// The string persisted in `PercentInputs.mode`, decoupled from the display title.
    var storedName: String {
        switch self {
        case .margin: return "margin"
        case .change: return "change"
        case .breakEven: return "breakEven"
        }
    }
}
