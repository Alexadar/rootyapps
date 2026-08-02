import SwiftUI
import AmortKit

/// The schedule as a real, scrollable table — not a register you step through one period at a time.
/// Every incumbent hides this; showing it is the point.
public struct AmortizationScreen: View {
    @StateObject private var model = AmortizationViewModel()
    @Binding private var document: TapeDocument
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public init(document: Binding<TapeDocument>) {
        self._document = document
    }

    @State private var share: ShareItem?

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                inputs
                frequency
                hero
                totals
                granularity
                table
                AppendToTapeBar(label: $model.rowLabel, canAppend: model.tapeRow() != nil,
                                identifier: "amort.tape") { append() }
                ProvenanceStrip(authorities: model.authorities, conventions: model.conventions,
                                identifier: "amort.provenance")
            }
            .padding(.horizontal, Par.Metrics.gutter)
            .padding(.bottom, 12)
        }
        .background(Par.Palette.base)
        .sheet(item: $share) { ExportSheet(item: $0) }
        .navigationTitle("Amortization")
    }

    private var inputs: some View {
        VStack(spacing: 0) {
            NumberField("PV", caption: "loan amount", unit: "USD",
                        value: $model.principal, range: AmortizationViewModel.principalRange,
                        digits: 2, identifier: "amort.input.principal")
            Divider().overlay(Par.Palette.separator)
            NumberField("i%", caption: "annual rate", unit: "nominal",
                        value: $model.annualRatePct, range: AmortizationViewModel.ratePctRange,
                        digits: 3, identifier: "amort.input.rate")
            Divider().overlay(Par.Palette.separator)
            NumberField("n", caption: "payments", unit: "count",
                        value: periodsBinding, range: AmortizationViewModel.periodsRange,
                        digits: 0, identifier: "amort.input.periods")
            Divider().overlay(Par.Palette.separator)
            NumberField("BAL", caption: "balloon at maturity", unit: "USD",
                        value: $model.balloon, range: 0...1_000_000_000,
                        digits: 2, identifier: "amort.input.balloon")
        }
        .glassCard()
    }

    /// The payment frequency was fixed at 12 and settable by nothing, while it silently divides the
    /// annual rate into the periodic one. A quarterly or biweekly loan could not be amortized at all,
    /// and `n = 20` entered as years produced a twenty-month schedule.
    private var frequency: some View {
        SettingCard("payments / yr", value: String(model.periodsPerYear),
                    identifier: "amort.periodsPerYear",
                    spoken: "payments per year, \(model.periodsPerYear)") {
            Frequency.picker("payments / yr", selection: $model.periodsPerYear)
        }
    }

    private var periodsBinding: Binding<Double> {
        Binding(get: { Double(model.periods) }, set: { model.periods = max(Int($0), 1) })
    }

    private var hero: some View {
        HeroResult(
            caption: "PMT · level payment",
            value: Fmt.money(model.payment),
            footnote: "\(model.periods) payments · \(model.periodsPerYear) per year",
            identifier: "amort.hero",
            spoken: Fmt.spokenMoney(model.payment, label: "payment")
        )
    }

    private var totals: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { totalCards }
            VStack(spacing: 8) { totalCards }
        }
    }

    @ViewBuilder
    private var totalCards: some View {
        ResultRow("total interest", value: Fmt.money(model.totalInterest), unit: "USD",
                  emphasis: .strong, identifier: "amort.totalInterest",
                  spoken: Fmt.spokenMoney(model.totalInterest, label: "total interest"))
        ResultRow("total paid", value: Fmt.money(model.totalInterest + model.principal - model.balloon),
                  unit: "USD", identifier: "amort.totalPaid",
                  spoken: Fmt.spokenMoney(model.totalInterest + model.principal - model.balloon,
                                          label: "total paid"))
    }

    private var granularity: some View {
        HStack(spacing: 8) {
            SubScreenPicker(
                options: AmortizationViewModel.Granularity.allCases.map { ($0, $0.rawValue) },
                selection: $model.granularity,
                identifier: "amort.granularity"
            )
            scheduleExport
        }
    }

    /// The schedule leaves the screen.
    ///
    /// `TapeExport.csv(schedule:title:)` and `ScheduleLine` were written and had **zero callers**, so
    /// the per-period table — interest, principal, balance, the thing anyone actually wants in a
    /// spreadsheet — could only ever be read off the display. The tape carries one summary line per
    /// amortization row, which is not the same artefact at all.
    private var scheduleExport: some View {
        Menu {
            Button("Print schedule", systemImage: "printer") {
                PlainTextPrinter.print(scheduleText, jobName: scheduleTitle)
            }
            Button("Export CSV", systemImage: "tablecells") {
                share = ShareItem(text: scheduleCSV,
                                  suggestedName: scheduleTitle
                                      .replacingOccurrences(of: "/", with: "-") + ".csv")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.subheadline)
                .foregroundStyle(Par.Palette.labelSecondary)
                .frame(minWidth: Par.Metrics.minHitTarget, minHeight: Par.Metrics.minHitTarget)
        }
        .accessibilityIdentifier("amort.export")
        .accessibilityLabel("Print or export the schedule")
    }

    private var scheduleTitle: String {
        let base = model.rowLabel.isEmpty ? "Amortization schedule" : model.rowLabel
        return "\(base) — \(Fmt.money(model.principal, digits: 0)) at \(Fmt.percent(model.annualRatePct, digits: 3))"
    }

    /// Every period, whatever the table is currently showing: a by-year view on screen is a reading
    /// convenience, not a reason to export a coarser file than the borrower asked for.
    private var scheduleLines: [TapeExport.ScheduleLine] {
        model.schedule.map { period in
            TapeExport.ScheduleLine(
                period: period.index,
                payment: Fmt.money(period.payment),
                interest: Fmt.money(period.interest),
                principal: Fmt.money(period.principal),
                balance: Fmt.money(period.balance)
            )
        }
    }

    private var scheduleCSV: String {
        TapeExport.csv(schedule: scheduleLines, title: scheduleTitle)
    }

    private var scheduleText: String {
        var lines = [scheduleTitle, ""]
        lines.append("period      payment     interest    principal      balance")
        for line in scheduleLines {
            lines.append([
                line.period.description.padding(toLength: 8, withPad: " ", startingAt: 0),
                line.payment.leftPadded(to: 12), line.interest.leftPadded(to: 12),
                line.principal.leftPadded(to: 12), line.balance.leftPadded(to: 13),
            ].joined())
        }
        return lines.joined(separator: "\n")
    }

    @ViewBuilder
    private var table: some View {
        // Lazy, because "Every period" on a 1,200-payment loan builds 1,200 `ViewThatFits` rows of
        // five `Text`s each — eagerly, inside a ScrollView, which hangs for seconds. The range
        // allows n up to 1,200, so this is reachable by anyone poking at the maximum.
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            ScheduleHeaderRow(leading: model.granularity == .byYear ? "year" : "period")
            Divider().overlay(Par.Palette.separator)
            if model.granularity == .byYear {
                ForEach(model.years, id: \.self) { year in
                    let totals = model.yearTotals(year)
                    ScheduleTableRow(
                        leading: "\(year)",
                        payment: Fmt.money(totals.payments),
                        interest: Fmt.money(totals.interest),
                        principal: Fmt.money(totals.principal),
                        balance: Fmt.money(totals.closingBalance),
                        identifier: "amort.year.\(year)"
                    )
                    Divider().overlay(Par.Palette.separator)
                }
            } else {
                ForEach(model.schedule, id: \.index) { period in
                    ScheduleTableRow(
                        leading: "\(period.index)",
                        payment: Fmt.money(period.payment),
                        interest: Fmt.money(period.interest),
                        principal: Fmt.money(period.principal),
                        balance: Fmt.money(period.balance),
                        identifier: "amort.period.\(period.index)"
                    )
                    Divider().overlay(Par.Palette.separator)
                }
            }
        }
        .glassCard()
    }

    private func append() {
        if let row = model.tapeRow() { document.append(row) }
    }
}

/// One row of a schedule. Shared by the amortization and depreciation tables so a table reads the
/// same way whichever Kit filled it.
struct ScheduleTableRow: View {
    let leading: String
    let payment: String
    let interest: String
    let principal: String
    let balance: String
    let identifier: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                cell(leading, width: 44, alignment: .leading, secondary: true)
                cell(payment, alignment: .trailing)
                cell(interest, alignment: .trailing)
                cell(principal, alignment: .trailing)
                cell(balance, alignment: .trailing, strong: true)
            }
            // Narrow widths stack rather than truncate: a schedule that clips is the incumbent's bug.
            VStack(alignment: .leading, spacing: 2) {
                Text(leading).font(.caption.weight(.semibold)).foregroundStyle(Par.Palette.labelSecondary)
                HStack { Text("payment"); Spacer(); Text(payment) }
                HStack { Text("interest"); Spacer(); Text(interest) }
                HStack { Text("principal"); Spacer(); Text(principal) }
                HStack { Text("balance"); Spacer(); Text(balance).foregroundStyle(Par.Palette.label) }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(Par.Palette.labelSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
        // The wide layout's column headers are decorative and hidden, and combining the children
        // leaves VoiceOver reading five unlabelled numbers. Name them here instead, in the order
        // they are read.
        .accessibilityLabel("\(leading). payment \(payment), interest \(interest), "
                            + "principal \(principal), balance \(balance)")
    }

    private func cell(_ text: String, width: CGFloat? = nil,
                      alignment: Alignment = .trailing, secondary: Bool = false,
                      strong: Bool = false) -> some View {
        Text(text)
            .font(.caption.monospacedDigit().weight(strong ? .semibold : .regular))
            .foregroundStyle(secondary ? Par.Palette.labelSecondary
                             : (strong ? Par.Palette.label : Par.Palette.labelSecondary))
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
            .lineLimit(1)
    }
}

struct ScheduleHeaderRow: View {
    let leading: String

    var body: some View {
        HStack(spacing: 10) {
            Text(leading).frame(width: 44, alignment: .leading)
            Text("payment").frame(maxWidth: .infinity, alignment: .trailing)
            Text("interest").frame(maxWidth: .infinity, alignment: .trailing)
            Text("principal").frame(maxWidth: .infinity, alignment: .trailing)
            Text("balance").frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.caption2)
        .foregroundStyle(Par.Palette.labelTertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .accessibilityHidden(true)
    }
}

#Preview("Amortization — dark") {
    NavigationStack { AmortizationScreen(document: .constant(TapeDocument())) }.parAppearance()
}

#Preview("Amortization — AX5") {
    NavigationStack { AmortizationScreen(document: .constant(TapeDocument())) }
        .environment(\.dynamicTypeSize, .accessibility5)
        .parAppearance()
}

private extension String {
    /// Right-aligns a formatted figure in a fixed column, so a printed schedule's decimal points
    /// line up the way a printed schedule's decimal points are supposed to.
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}
