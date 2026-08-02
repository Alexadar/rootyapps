import Foundation
import SwiftUI
import RealEstateKit

/// Income-property underwriting: rent roll → NOI → value, and the two tests every commercial lender
/// applies. The screen's job is to show *which* test binds, because that is what a borrower
/// negotiates against.
@MainActor
public final class RealEstateViewModel: ObservableObject {

    @Published public var grossPotentialRent: Double = 518_400
    @Published public var vacancyPct: Double = 5
    @Published public var otherIncome: Double = 0
    @Published public var operatingExpenses: Double = 197_000
    @Published public var reserves: Double = 0
    @Published public var value: Double = 5_400_000
    @Published public var targetDSCR: Double = 1.25
    @Published public var maxLTVPct: Double = 75
    @Published public var annualRatePct: Double = 6.25
    @Published public var amortizationYears: Double = 30
    @Published public var rowLabel: String = ""

    public init() {}

    public static let moneyRange: ClosedRange<Double> = 0...1_000_000_000
    public static let valueRange: ClosedRange<Double> = 1...1_000_000_000
    // The Kit requires a vacancy fraction in [0, 1): a fully vacant building has no ratios.
    public static let vacancyRange: ClosedRange<Double> = 0...99.9
    public static let dscrRange: ClosedRange<Double> = 0.5...3
    public static let ltvRange: ClosedRange<Double> = 1...100
    public static let ratePctRange: ClosedRange<Double> = 0...30
    public static let amortRange: ClosedRange<Double> = 1...40

    public var netOperatingIncome: Double {
        RealEstate.netOperatingIncome(
            grossPotentialRent: grossPotentialRent, vacancyRate: min(vacancyPct, 99.9) / 100,
            otherIncome: otherIncome, operatingExpenses: operatingExpenses, reserves: reserves
        )
    }

    public var effectiveGrossIncome: Double {
        RealEstate.effectiveGrossIncome(grossPotentialRent: grossPotentialRent,
                                        vacancyRate: min(vacancyPct, 99.9) / 100,
                                        otherIncome: otherIncome)
    }

    public var capRate: Double {
        RealEstate.capRate(netOperatingIncome: netOperatingIncome, value: max(value, 1))
    }

    public var mortgageConstant: Double {
        RealEstate.mortgageConstant(annualRatePct: annualRatePct,
                                    amortizationYears: max(amortizationYears, 0.01))
    }

    public enum Outcome: Equatable {
        case sized(RealEstate.LoanSizing)
        case failed(String)
    }

    public var outcome: Outcome {
        guard netOperatingIncome > 0 else {
            return .failed("This rent roll produces no net operating income, so it supports no loan.")
        }
        return .sized(RealEstate.sizeLoan(
            netOperatingIncome: netOperatingIncome, value: max(value, 1),
            targetDSCR: targetDSCR, maxLTV: maxLTVPct / 100,
            annualRatePct: annualRatePct, amortizationYears: max(amortizationYears, 0.01)
        ))
    }

    public var annualDebtService: Double {
        guard case .sized(let sizing) = outcome else { return 0 }
        return RealEstate.annualDebtService(loan: sizing.loan, annualRatePct: annualRatePct,
                                            amortizationYears: max(amortizationYears, 0.01))
    }

    public var cashFlowBeforeTax: Double {
        RealEstate.cashFlowBeforeTax(netOperatingIncome: netOperatingIncome,
                                     annualDebtService: annualDebtService)
    }

    public var cashOnCash: Double {
        guard case .sized(let sizing) = outcome else { return 0 }
        let equity = max(value - sizing.loan, 1)
        return RealEstate.cashOnCash(cashFlowBeforeTax: cashFlowBeforeTax, cashInvested: equity) * 100
    }

    public var breakEvenOccupancy: Double {
        guard grossPotentialRent > 0 else { return 0 }
        return RealEstate.breakEvenOccupancy(operatingExpenses: operatingExpenses,
                                             annualDebtService: annualDebtService,
                                             grossPotentialRent: grossPotentialRent) * 100
    }

    /// Leverage only helps when the asset out-yields the debt — the sentence that decides a deal.
    public var leverageIsAccretive: Bool {
        RealEstate.leveragedReturnIsPositive(capRate: capRate, mortgageConstant: mortgageConstant)
    }

    public var bindingTest: String {
        guard case .sized(let sizing) = outcome else { return "—" }
        return sizing.dscrConstrained ? "coverage binds" : "loan-to-value binds"
    }

    public var authorities: [String] { ["definition · no published worked example obtained"] }

    public var conventions: [String] {
        ["annual figures", "NOI before debt service and tax",
         "reserves treated as an operating cost", bindingTest]
    }

    public func tapeRow() -> TapeRow? {
        guard case .sized = outcome else { return nil }
        return TapeRow(label: rowLabel, inputs: .realEstate(RealEstateInputs(
            grossPotentialRent: grossPotentialRent, vacancyPct: vacancyPct,
            otherIncome: otherIncome, operatingExpenses: operatingExpenses, reserves: reserves,
            value: value, targetDSCR: targetDSCR, maxLTVPct: maxLTVPct,
            annualRatePct: annualRatePct, amortizationYears: amortizationYears
        )))
    }
}
