import Foundation
import SwiftUI
import CashFlowKit

@MainActor
public final class CashFlowViewModel: ObservableObject {

    @Published public var groups: [CashFlow.Group] = [
        .init(amount: -250_000, count: 1),
        .init(amount:   24_000, count: 4),
        .init(amount:   31_500, count: 6),
        .init(amount:        0, count: 1),
        .init(amount:  318_000, count: 1)
    ]
    @Published public var discountRatePct: Double = 8
    @Published public var financeRatePct: Double = 8
    @Published public var reinvestRatePct: Double = 6
    @Published public var rowLabel: String = ""

    public init() {}

    public static let ratePctRange: ClosedRange<Double> = -99...200
    public static let amountRange: ClosedRange<Double> = -1_000_000_000...1_000_000_000
    public static let countRange: ClosedRange<Double> = 1...999

    private var flows: [Double] { CashFlow.expand(groups) }

    public var npv: Double { CashFlow.npv(rate: discountRatePct / 100, flows: flows) }
    public var nfv: Double { CashFlow.nfv(rate: discountRatePct / 100, flows: flows) }
    public var mirr: Double? {
        CashFlow.mirr(flows: flows, financeRate: financeRatePct / 100, reinvestRate: reinvestRatePct / 100)
    }
    public var payback: Double? { CashFlow.payback(flows: flows) }
    public var discountedPayback: Double? {
        CashFlow.discountedPayback(flows: flows, rate: discountRatePct / 100)
    }
    public var irr: CashFlow.IRRResult { CashFlow.irr(flows: flows) }

    /// "This loan has two internal rates of return" is information the
    /// professional wants. Picking one silently is the behaviour Par replaces.
    public enum IRRPresentation: Equatable {
        case unique(Double)
        case multiple([Double])
        case none
    }

    public var irrPresentation: IRRPresentation {
        switch irr {
        case .unique(let r): return .unique(r)
        case .multiple(let rs): return .multiple(rs)
        case .none: return .none
        }
    }

    public var signChanges: Int {
        var changes = 0
        var previous: Double?
        for flow in flows where flow != 0 {
            if let p = previous, (p < 0) != (flow < 0) { changes += 1 }
            previous = flow
        }
        return changes
    }

    public var authorities: [String] {
        ["12 CFR 1026 App J (c)(6)", "NIST HB 135e2025 §7.1.1"]
    }

    public var conventions: [String] {
        ["annual periods", "flows at period end",
         "discount rate \(Fmt.percent(discountRatePct, digits: 2))",
         signChanges > 1 ? "\(signChanges) sign changes — more than one IRR is possible"
                         : "one sign change"]
    }

    /// Inputs only — never the result.
    public func tapeRow() -> TapeRow? {
        guard !groups.isEmpty else { return nil }
        return TapeRow(label: rowLabel, inputs: .cashFlow(CashFlowInputs(
            groups: groups.map { .init(amount: $0.amount, count: $0.count) },
            discountRatePct: discountRatePct,
            financeRatePct: financeRatePct,
            reinvestRatePct: reinvestRatePct
        )))
    }
}
