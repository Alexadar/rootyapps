import SwiftUI
import CashFlowKit

/// Uneven cash flows as a visible, editable list — the CFj/Nj model without the hidden registers.
public struct CashFlowScreen: View {
    @StateObject private var model = CashFlowViewModel()
    @Binding private var document: TapeDocument

    public init(document: Binding<TapeDocument>) {
        self._document = document
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                rate
                hero
                measures
                flowList
                AppendToTapeBar(label: $model.rowLabel, canAppend: model.tapeRow() != nil,
                                identifier: "cashflow.tape") { append() }
                ProvenanceStrip(authorities: model.authorities, conventions: model.conventions,
                                identifier: "cashflow.provenance")
            }
            .padding(.horizontal, Par.Metrics.gutter)
            .padding(.bottom, 12)
        }
        .background(Par.Palette.base)
        .navigationTitle("Cash Flow")
    }

    private var rate: some View {
        VStack(spacing: 0) {
            NumberField("i%", caption: "discount rate", unit: "per period",
                        value: $model.discountRatePct, range: CashFlowViewModel.ratePctRange,
                        digits: 3, identifier: "cashflow.input.rate")
            Divider().overlay(Par.Palette.separator)
            NumberField("FIN", caption: "finance rate", unit: "MIRR",
                        value: $model.financeRatePct, range: CashFlowViewModel.ratePctRange,
                        digits: 3, identifier: "cashflow.input.financeRate")
            Divider().overlay(Par.Palette.separator)
            NumberField("REI", caption: "reinvestment rate", unit: "MIRR",
                        value: $model.reinvestRatePct, range: CashFlowViewModel.ratePctRange,
                        digits: 3, identifier: "cashflow.input.reinvestRate")
        }
        .glassCard()
    }

    /// Multiple roots and no root are answers, not errors — and never a silently chosen number.
    @ViewBuilder
    private var hero: some View {
        switch model.irrPresentation {
        case .unique(let rate):
            HeroResult(caption: "IRR · internal rate of return",
                       value: Fmt.percent(rate * 100),
                       footnote: "NPV is zero at this rate",
                       identifier: "cashflow.hero",
                       spoken: Fmt.spokenPercent(rate * 100, label: "internal rate of return"))
        case .multiple(let roots):
            MultipleIRRNotice(roots: roots.map { $0 * 100 }, signChanges: model.signChanges)
        case .none:
            FailureNotice(
                title: "No rate satisfies these flows",
                detail: "Every flow has the same sign, or the series never crosses zero. There is no "
                    + "internal rate of return to report, and Par will not invent one.",
                technical: "CashFlow.IRRResult.none · \(model.signChanges) sign changes",
                identifier: "cashflow.hero.failure"
            )
        }
    }

    private var measures: some View {
        VStack(spacing: 0) {
            ResultRow("NPV", value: Fmt.money(model.npv), unit: "USD", emphasis: .strong,
                      identifier: "cashflow.npv",
                      spoken: Fmt.spokenMoney(model.npv, label: "net present value"))
            Divider().overlay(Par.Palette.separator)
            ResultRow("NFV", value: Fmt.money(model.nfv), unit: "USD",
                      identifier: "cashflow.nfv",
                      spoken: Fmt.spokenMoney(model.nfv, label: "net future value"))
            Divider().overlay(Par.Palette.separator)
            ResultRow("MIRR", value: model.mirr.map { Fmt.percent($0 * 100) } ?? "—",
                      identifier: "cashflow.mirr",
                      spoken: model.mirr.map { Fmt.spokenPercent($0 * 100, label: "modified internal rate") }
                        ?? "modified internal rate of return, undefined")
            Divider().overlay(Par.Palette.separator)
            ResultRow("payback", value: model.payback.map { Fmt.count($0) } ?? "never",
                      unit: "periods", identifier: "cashflow.payback",
                      spoken: model.payback.map { "payback in \(Fmt.count($0)) periods" }
                        ?? "never pays back")
            Divider().overlay(Par.Palette.separator)
            ResultRow("discounted payback",
                      value: model.discountedPayback.map { Fmt.count($0) } ?? "never",
                      unit: "periods", identifier: "cashflow.discountedPayback",
                      spoken: model.discountedPayback.map { "discounted payback in \(Fmt.count($0)) periods" }
                        ?? "never pays back once discounted")
        }
        .glassCard()
    }

    private var flowList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("cash flows").font(.caption2).foregroundStyle(Par.Palette.labelTertiary)
                Spacer()
                Button {
                    model.groups.append(.init(amount: 0, count: 1))
                } label: {
                    Label("Add group", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Par.Palette.accent)
                .accessibilityIdentifier("cashflow.addGroup")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider().overlay(Par.Palette.separator)

            ForEach(Array(model.groups.enumerated()), id: \.offset) { index, group in
                CashFlowGroupRow(
                    index: index,
                    amount: Binding(
                        get: { model.groups[index].amount },
                        set: { model.groups[index] = .init(amount: $0, count: model.groups[index].count) }
                    ),
                    count: Binding(
                        get: { Double(model.groups[index].count) },
                        set: { model.groups[index] = .init(amount: model.groups[index].amount,
                                                           count: max(Int($0), 1)) }
                    ),
                    canRemove: model.groups.count > 1
                ) {
                    model.groups.remove(at: index)
                }
                Divider().overlay(Par.Palette.separator)
            }
        }
        .glassCard()
    }

    private func append() {
        if let row = model.tapeRow() { document.append(row) }
    }
}

struct CashFlowGroupRow: View {
    let index: Int
    @Binding var amount: Double
    @Binding var count: Double
    let canRemove: Bool
    let remove: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            NumberField("CF\(index)", caption: index == 0 ? "initial flow" : "flow amount",
                        unit: "USD", value: $amount,
                        range: CashFlowViewModel.amountRange, digits: 2,
                        identifier: "cashflow.input.amount.\(index)")
            Divider().overlay(Par.Palette.separator)
            HStack {
                NumberField("N\(index)", caption: "consecutive occurrences", unit: "count",
                            value: $count, range: CashFlowViewModel.countRange, digits: 0,
                            identifier: "cashflow.input.count.\(index)")
                if canRemove {
                    Button(role: .destructive, action: remove) {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Par.Palette.labelTertiary)
                    .padding(.trailing, 12)
                    .accessibilityLabel("Remove flow group \(index)")
                    .accessibilityIdentifier("cashflow.removeGroup.\(index)")
                }
            }
        }
    }
}

#Preview("Cash Flow — dark") {
    NavigationStack { CashFlowScreen(document: .constant(TapeDocument())) }.parAppearance()
}

#Preview("Cash Flow — AX5") {
    NavigationStack { CashFlowScreen(document: .constant(TapeDocument())) }
        .environment(\.dynamicTypeSize, .accessibility5)
        .parAppearance()
}
