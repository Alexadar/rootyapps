import SwiftUI
import TVMKit

/// One solved problem, on one line.
public struct TapeRowView: View {
    @Binding private var row: TapeRow
    private let isEditing: Bool

    public init(row: Binding<TapeRow>, isEditing: Bool) {
        self._row = row
        self.isEditing = isEditing
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: isEditing ? 9 : 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    labelView
                    Text(inputSummary)
                        .font(.caption.monospaced())
                        .foregroundStyle(Par.Palette.labelSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(resultName).font(.caption2).foregroundStyle(Par.Palette.labelTertiary)
                    Text(resultValue)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Par.Palette.label)
                        .accessibilityIdentifier("tape.row.result.\(row.id.uuidString)")
                }
            }

            if isEditing { editor }
        }
        .padding(.vertical, 4)
        .background(isEditing ? Par.Palette.accentTint : .clear)
        .overlay(alignment: .leading) {
            if isEditing { Rectangle().fill(Par.Palette.accent).frame(width: 2.5) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tape.row.\(row.id.uuidString)")
    }

    @ViewBuilder
    private var labelView: some View {
        if row.label.isEmpty {
            Text("no label").font(.subheadline.italic()).foregroundStyle(Par.Palette.labelTertiary)
        } else {
            Text(row.label).font(.subheadline.weight(.semibold)).foregroundStyle(Par.Palette.label)
                .lineLimit(isEditing ? nil : 1)
        }
    }

    /// Editing a row re-solves that row only.
    @ViewBuilder
    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Label this solve", text: $row.label)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(Par.Palette.label)
                .accessibilityIdentifier("tape.row.label.\(row.id.uuidString)")

            if case .damaged(let damaged) = row.inputs {
                FailureNotice(
                    title: "This line can’t be read back",
                    detail: "\(damaged.reason) The rest of the tape is intact. Par will not guess a value, and it will not delete your line.",
                    technical: damaged.rawSummary,
                    identifier: "tape.row.damaged.\(row.id.uuidString)",
                    isWarning: true
                )
            } else {
                Text("Change any input above and this row re-solves. Nothing else on the tape moves.")
                    .font(.caption)
                    .foregroundStyle(Par.Palette.labelSecondary)
            }
        }
    }

    // MARK: - Presentation. Re-derived, never cached.

    private var inputSummary: String {
        switch row.inputs {
        case .tvm(let i):
            return "TVM · n \(Fmt.count(i.periods)) · i \(Fmt.money(i.annualRatePct, digits: 2)) · PV \(Fmt.money(i.presentValue, digits: 0)) · FV \(Fmt.money(i.futureValue, digits: 0))"
        case .amortization(let i):
            return "Amort · n \(i.periods) · i \(Fmt.money(i.annualRatePct, digits: 2)) · PV \(Fmt.money(i.principal, digits: 0))"
        case .cashFlow(let i):
            return "Cash Flow · \(i.groups.count) groups · rate \(Fmt.money(i.discountRatePct, digits: 2))"
        case .bond(let i):
            return "Bond · price \(Fmt.price(i.price, digits: 3)) · coupon \(Fmt.money(i.couponPct, digits: 2)) · \(i.conventionRawValue)"
        case .damaged(let d):
            return d.rawSummary
        }
    }

    private var resultName: String {
        switch row.inputs {
        case .tvm(let i): return i.solveFor.uppercased()
        case .amortization: return "Balance"
        case .cashFlow: return "IRR"
        case .bond: return "YTM"
        case .damaged: return "—"
        }
    }

    /// Re-run the Kit here. Never store what you cannot regenerate.
    private var resultValue: String {
        switch row.inputs {
        case .tvm(let i):
            let registers = TVM.Registers(
                periods: i.periods, annualRatePct: i.annualRatePct, presentValue: i.presentValue,
                payment: i.payment, futureValue: i.futureValue,
                paymentsPerYear: i.paymentsPerYear, compoundsPerYear: i.compoundsPerYear,
                timing: i.timingIsBeginning ? .beginning : .end
            )
            guard let variable = TVM.Variable(rawValue: i.solveFor),
                  let value = try? TVM.solve(for: variable, registers) else { return "—" }
            return variable == .annualRatePct ? Fmt.percent(value) : Fmt.money(value)
        case .damaged:
            return "—"
        default:
            return "—"   // wire the remaining Kits the same way
        }
    }
}
