import Foundation
import SwiftUI
import TVMKit

/// Zero math in views. This holds `@Published` inputs and exposes *computed*
/// outputs that call the Kit; the view formats and displays, never calculates.
@MainActor
public final class TVMViewModel: ObservableObject {

    @Published public var periods: Double = 360
    @Published public var annualRatePct: Double = 6.25
    @Published public var presentValue: Double = 420_000
    @Published public var payment: Double = 0
    @Published public var futureValue: Double = 0
    @Published public var paymentsPerYear: Int = 12
    @Published public var compoundsPerYear: Int = 12
    @Published public var timing: TVM.Timing = .end
    @Published public var solveFor: TVM.Variable = .payment
    @Published public var rowLabel: String = ""

    public init() {}

    // MARK: - Bounds. The field's job is to make an illegal value un-enterable.

    public static let periodsRange: ClosedRange<Double> = 0...1_200
    public static let ratePctRange: ClosedRange<Double> = -99...200
    public static let moneyRange: ClosedRange<Double> = -1_000_000_000...1_000_000_000

    // MARK: - Kit call

    private var registers: TVM.Registers {
        TVM.Registers(
            periods: periods,
            annualRatePct: annualRatePct,
            presentValue: presentValue,
            payment: payment,
            futureValue: futureValue,
            paymentsPerYear: paymentsPerYear,
            compoundsPerYear: compoundsPerYear,
            timing: timing
        )
    }

    public enum Outcome: Equatable {
        case solved(Double)
        /// Solves that can fail, fail visibly. Never a fabricated fallback number.
        case failed(String)
    }

    /// Computed, not stored: the result is always re-derived from the inputs.
    public var outcome: Outcome {
        do {
            return .solved(try TVM.solve(for: solveFor, registers))
        } catch let error as TVM.SolveError {
            return .failed(error.description)
        } catch {
            return .failed("This combination has no solution.")
        }
    }

    // MARK: - Presentation strings (formatting only)

    public var solveTargetSymbol: String {
        switch solveFor {
        case .periods: return "n"
        case .annualRatePct: return "i%"
        case .presentValue: return "PV"
        case .payment: return "PMT"
        case .futureValue: return "FV"
        }
    }

    public var solveTargetCaption: String {
        switch solveFor {
        case .periods: return "number of periods"
        case .annualRatePct: return "annual rate, nominal"
        case .presentValue: return "present value"
        case .payment: return "payment, \(timing == .end ? "end" : "beginning") of period"
        case .futureValue: return "future value"
        }
    }

    public var heroValue: String {
        guard case .solved(let value) = outcome else { return "—" }
        switch solveFor {
        case .periods: return Fmt.count(value)
        case .annualRatePct: return Fmt.percent(value, digits: 3)
        default: return Fmt.money(value)
        }
    }

    public var heroFootnote: String {
        guard case .solved(let value) = outcome else { return "no solution" }
        switch solveFor {
        case .periods: return "periods at \(paymentsPerYear) per year"
        case .annualRatePct: return "nominal, compounded \(compoundsPerYear)× per year"
        default: return "\(Fmt.direction(value)) · USD"
        }
    }

    public var spokenHero: String {
        guard case .solved(let value) = outcome else { return "\(solveTargetCaption), no solution" }
        switch solveFor {
        case .annualRatePct: return Fmt.spokenPercent(value, label: solveTargetCaption)
        case .periods: return "\(solveTargetCaption), \(Fmt.count(value))"
        default: return Fmt.spokenMoney(value, label: solveTargetCaption)
        }
    }

    public var conventions: [String] {
        ["\(paymentsPerYear) payments / \(compoundsPerYear) compounds per year",
         timing == .end ? "payments at period end" : "payments at period beginning",
         "nominal rate"]
    }

    /// Inputs only — never the result.
    public func tapeRow() -> TapeRow? {
        guard case .solved = outcome else { return nil }
        return TapeRow(
            label: rowLabel,
            inputs: .tvm(TVMInputs(
                periods: periods, annualRatePct: annualRatePct, presentValue: presentValue,
                payment: payment, futureValue: futureValue, paymentsPerYear: paymentsPerYear,
                compoundsPerYear: compoundsPerYear, timingIsBeginning: timing == .beginning,
                solveFor: solveFor.rawValue
            ))
        )
    }
}
