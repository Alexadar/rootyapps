import Foundation
import SwiftUI
import RateKit

/// Regulation Z's annual percentage rate, Regulation DD's annual percentage yield, and the
/// conversion between a nominal and an effective rate. Zero math here: every output is a computed
/// call into `RateKit`.
@MainActor
public final class RateViewModel: ObservableObject {

    public enum Mode: String, CaseIterable, Hashable {
        case apr = "APR"
        case apy = "APY"
        case convert = "Convert"
    }

    @Published public var mode: Mode = .apr
    @Published public var rowLabel: String = ""

    // APR — a single advance repaid by a level series (Reg Z App J (c)(1)).
    @Published public var advance: Double = 5_000
    @Published public var payment: Double = 230
    @Published public var paymentCount: Double = 24
    @Published public var unitPeriodsPerYear: Double = 12

    // APY — Reg DD App A.
    @Published public var interest: Double = 61.68
    @Published public var principal: Double = 1_000
    @Published public var daysInTerm: Double = 365

    // Nominal ↔ effective.
    @Published public var nominalPct: Double = 6
    @Published public var timesPerYear: Double = 12

    public init() {}

    // Ranges respect the Kit's preconditions, not merely what looks reasonable.
    public static let moneyRange: ClosedRange<Double> = 0.01...1_000_000_000
    public static let interestRange: ClosedRange<Double> = 0...1_000_000_000
    public static let countRange: ClosedRange<Double> = 1...600
    public static let daysRange: ClosedRange<Double> = 1...36_500
    public static let frequencyRange: ClosedRange<Double> = 1...365
    public static let ratePctRange: ClosedRange<Double> = -99...200

    public enum Outcome: Equatable {
        case solved(Double)
        case failed(String)
    }

    public var outcome: Outcome {
        switch mode {
        case .apr:
            do {
                let value = try Rate.aprActuarial(
                    advances: [.init(amount: advance, fullPeriods: 0)],
                    payments: Rate.series(amount: payment, count: Int(paymentCount),
                                          firstAtFullPeriods: 1),
                    unitPeriodsPerYear: unitPeriodsPerYear
                )
                return .solved(value)
            } catch let error as Rate.RateError {
                return .failed(error.description)
            } catch {
                return .failed("These payments never balance the advance.")
            }
        case .apy:
            return .solved(Rate.apy(interest: interest, principal: principal, daysInTerm: daysInTerm))
        case .convert:
            return .solved(Rate.effectiveAnnualRate(nominalPct: nominalPct,
                                                    timesPerYear: Int(timesPerYear)))
        }
    }

    /// The inverse direction, run on the *same typed number* read the other way: if the rate in the
    /// field were an effective rate, this is the nominal that produces it.
    ///
    /// It is deliberately not the inverse of the hero — inverting the hero would simply give back
    /// the input. The row used to be labelled "nominal for this effective", which reads as exactly
    /// that round trip and made the number look wrong. The screen has one rate field, so the honest
    /// framing is the what-if, and the label now says so.
    public var nominalIfRateWereEffective: Double {
        Rate.nominalAnnualRate(effectivePct: nominalPct, timesPerYear: Int(timesPerYear))
    }

    public var continuousEquivalent: Double {
        Rate.effectiveAnnualRateContinuous(nominalPct: nominalPct)
    }

    public var totalOfPayments: Double { payment * paymentCount }
    public var financeCharge: Double { totalOfPayments - advance }

    public var heroCaption: String {
        switch mode {
        case .apr: return "APR · annual percentage rate"
        case .apy: return "APY · annual percentage yield"
        case .convert: return "effective annual rate"
        }
    }

    public var heroFootnote: String {
        switch mode {
        case .apr: return "actuarial method · 12 CFR 1026 App J"
        case .apy: return "365-day exponent · 12 CFR 1030 App A"
        case .convert: return "\(Int(timesPerYear))× per year, compounded"
        }
    }

    public var authorities: [String] {
        switch mode {
        case .apr: return ["12 CFR 1026 App J (c)"]
        case .apy: return ["12 CFR 1030 App A"]
        case .convert: return ["definition · (1 + r/m)^m − 1"]
        }
    }

    public var conventions: [String] {
        switch mode {
        case .apr:
            return ["actuarial method", "simple interest on any fractional period",
                    "\(Fmt.count(unitPeriodsPerYear)) unit-periods per year",
                    "Reg Z tolerance is ⅛ point — not used here"]
        case .apy:
            return ["365-day exponent, leap years included", "interest already earned"]
        case .convert:
            return ["nominal in, effective out", "\(Int(timesPerYear)) compounds per year"]
        }
    }

    public func tapeRow() -> TapeRow? {
        guard case .solved = outcome else { return nil }
        return TapeRow(label: rowLabel, inputs: .rate(RateInputs(
            mode: mode == .apr ? "apr" : (mode == .apy ? "apy" : "convert"),
            advance: advance, payment: payment, paymentCount: Int(paymentCount),
            firstPaymentAtPeriod: 1, unitPeriodsPerYear: unitPeriodsPerYear,
            interest: interest, principal: principal, daysInTerm: daysInTerm,
            nominalPct: nominalPct, timesPerYear: Int(timesPerYear)
        )))
    }
}
