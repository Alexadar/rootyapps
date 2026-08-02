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

    /// Which register the keypad is typing into. Never the solve target — that one is the answer.
    @Published public var entryTarget: TVM.Variable = .presentValue
    /// Digits typed since the register was selected. Nil means the register still shows its stored
    /// value and the first keystroke replaces it, which is how every calculator behaves.
    @Published public var entryBuffer: String?

    public init() {}

    // MARK: - Bounds. The field's job is to make an illegal value un-enterable.

    public static let periodsRange: ClosedRange<Double> = 0...1_200
    public static let ratePctRange: ClosedRange<Double> = -99...200
    public static let moneyRange: ClosedRange<Double> = -1_000_000_000...1_000_000_000

    // MARK: - Keypad entry
    //
    // The keypad edits one register at a time and commits on every keystroke, so the hero recomputes
    // as you type rather than on an equals key. Entry is clamped to the same range the field
    // enforces: the Kit's preconditions are never reachable from the keypad either.

    /// Choose which register the app solves for. `TVMKit` has always solved for any of the five;
    /// until now nothing could change this from `.payment`, so four fifths of the screen's stated
    /// purpose was unreachable.
    public func solve(for variable: TVM.Variable) {
        guard variable != solveFor else { return }
        solveFor = variable
        // The answer is never the register you are typing into. If the keypad was aimed at the new
        // target, move it to the first register that is now an input.
        if entryTarget == variable {
            entryTarget = [.presentValue, .payment, .periods, .ratePct, .futureValue]
                .first { $0 != variable } ?? .presentValue
            entryBuffer = nil
        }
    }

    public func select(_ variable: TVM.Variable) {
        guard variable != solveFor else { return }      // the answer is not an input
        entryTarget = variable
        entryBuffer = nil
    }

    public func digit(_ value: Int) {
        appendToBuffer(String(value))
    }

    public func decimalPoint() {
        let current = entryBuffer ?? ""
        guard !current.contains(".") else { return }
        entryBuffer = current.isEmpty ? "0." : current + "."
        commitBuffer()
    }

    public func toggleSign() {
        var current = entryBuffer ?? formatted(entryTarget)
        if current.hasPrefix("-") { current.removeFirst() } else { current = "-" + current }
        entryBuffer = current
        commitBuffer()
    }

    public func backspace() {
        var current = entryBuffer ?? formatted(entryTarget)
        current = String(current.dropLast())
        entryBuffer = current
        commitBuffer()
    }

    public func clearEntry() {
        entryBuffer = ""
    }

    private func appendToBuffer(_ text: String) {
        entryBuffer = (entryBuffer ?? "") + text
        commitBuffer()
    }

    /// The buffer is the truth while typing; the register follows it, clamped.
    private func commitBuffer() {
        // "", "-" and "." are a keystroke on the way to a number, not a number. The register keeps
        // what it had until one actually arrives.
        guard let parsed = Double(entryBuffer ?? "") else { return }
        let clamped = min(max(parsed, range(for: entryTarget).lowerBound),
                          range(for: entryTarget).upperBound)
        switch entryTarget {
        case .periods: periods = clamped
        case .ratePct: annualRatePct = clamped
        case .presentValue: presentValue = clamped
        case .payment: payment = clamped
        case .futureValue: futureValue = clamped
        }
    }

    private func formatted(_ variable: TVM.Variable) -> String {
        let value = registers.value(of: variable)
        return value == value.rounded() ? String(Int(value)) : String(value)
    }

    public func range(for variable: TVM.Variable) -> ClosedRange<Double> {
        switch variable {
        case .periods: return Self.periodsRange
        case .ratePct: return Self.ratePctRange
        default: return Self.moneyRange
        }
    }

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
        case .ratePct: return "i%"
        case .presentValue: return "PV"
        case .payment: return "PMT"
        case .futureValue: return "FV"
        }
    }

    public var solveTargetCaption: String {
        switch solveFor {
        case .periods: return "number of periods"
        case .ratePct: return "annual rate, nominal"
        case .presentValue: return "present value"
        case .payment: return "payment, \(timing == .end ? "end" : "beginning") of period"
        case .futureValue: return "future value"
        }
    }

    public var heroValue: String {
        guard case .solved(let value) = outcome else { return "—" }
        switch solveFor {
        case .periods: return Fmt.count(value)
        case .ratePct: return Fmt.percent(value, digits: 3)
        default: return Fmt.money(value)
        }
    }

    public var heroFootnote: String {
        guard case .solved(let value) = outcome else { return "no solution" }
        switch solveFor {
        case .periods: return "periods at \(paymentsPerYear) per year"
        case .ratePct: return "nominal, compounded \(compoundsPerYear)× per year"
        default: return "\(Fmt.direction(value)) · USD"
        }
    }

    public var spokenHero: String {
        guard case .solved(let value) = outcome else { return "\(solveTargetCaption), no solution" }
        switch solveFor {
        case .ratePct: return Fmt.spokenPercent(value, label: solveTargetCaption)
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
                compoundsPerYear: compoundsPerYear, timingIsBeginning: timing == .begin,
                solveFor: solveFor.rawValue
            ))
        )
    }
}
