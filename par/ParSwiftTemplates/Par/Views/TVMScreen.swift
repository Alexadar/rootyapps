import SwiftUI
import TVMKit

/// The primary screen: five registers, one hero result.
public struct TVMScreen: View {
    @StateObject private var model = TVMViewModel()
    @Binding private var document: TapeDocument
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(document: Binding<TapeDocument>) {
        self._document = document
    }

    /// Three columns in a compact width (Split View, Slide Over, small window).
    private var keypadColumns: Int { horizontalSizeClass == .compact ? 3 : 4 }
    private var showsKeypad: Bool {
        #if os(macOS)
        false                       // hardware keys enter numbers on the Mac
        #else
        dynamicTypeSize < .accessibility3 || horizontalSizeClass != .compact ? true : true
        #endif
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    registers
                    frequencies
                    hero
                    ProvenanceStrip(
                        authorities: ["31 CFR 356 App B §II.A", "12 CFR 1030 App A"],
                        conventions: model.conventions,
                        identifier: "tvm.provenance"
                    )
                }
                .padding(.horizontal, Par.Metrics.gutter)
                .padding(.bottom, 12)
            }

            if showsKeypad {
                Keypad(solveTargetName: model.solveTargetSymbol, columns: keypadColumns) { key in
                    handle(key)
                }
            }
        }
        .background(Par.Palette.base)
        .navigationTitle("Time Value of Money")
    }

    private var registers: some View {
        VStack(spacing: 0) {
            NumberField("n", caption: "periods", unit: "months",
                        value: $model.periods, range: TVMViewModel.periodsRange, digits: 0,
                        isSolveTarget: model.solveFor == .periods,
                        identifier: "tvm.input.periods")
            Divider().overlay(Par.Palette.separator)
            NumberField("i%", caption: "annual rate", unit: "nominal",
                        value: $model.annualRatePct, range: TVMViewModel.ratePctRange, digits: 3,
                        isSolveTarget: model.solveFor == .annualRatePct,
                        identifier: "tvm.input.annualRate")
            Divider().overlay(Par.Palette.separator)
            NumberField("PV", caption: "present value", unit: "USD",
                        value: $model.presentValue, range: TVMViewModel.moneyRange,
                        isSolveTarget: model.solveFor == .presentValue,
                        identifier: "tvm.input.presentValue")
            Divider().overlay(Par.Palette.separator)
            NumberField("PMT", caption: "payment", unit: "USD",
                        value: $model.payment, range: TVMViewModel.moneyRange,
                        isSolveTarget: model.solveFor == .payment,
                        identifier: "tvm.input.payment")
            Divider().overlay(Par.Palette.separator)
            NumberField("FV", caption: "future value", unit: "USD",
                        value: $model.futureValue, range: TVMViewModel.moneyRange,
                        isSolveTarget: model.solveFor == .futureValue,
                        identifier: "tvm.input.futureValue")
        }
        .glassCard()
    }

    private var frequencies: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { frequencyCards }
            VStack(spacing: 8) { frequencyCards }
        }
    }

    @ViewBuilder
    private var frequencyCards: some View {
        ResultRow("payments / yr", value: String(model.paymentsPerYear),
                  identifier: "tvm.paymentsPerYear",
                  spoken: "payments per year, \(model.paymentsPerYear)")
        ResultRow("compounds / yr", value: String(model.compoundsPerYear),
                  identifier: "tvm.compoundsPerYear",
                  spoken: "compounding periods per year, \(model.compoundsPerYear)")
        ResultRow("timing", value: model.timing == .end ? "End" : "Begin",
                  identifier: "tvm.timing",
                  spoken: model.timing == .end ? "payments at end of period" : "payments at beginning of period")
    }

    @ViewBuilder
    private var hero: some View {
        switch model.outcome {
        case .solved:
            HeroResult(
                caption: "\(model.solveTargetSymbol) · \(model.solveTargetCaption)",
                value: model.heroValue,
                footnote: model.heroFootnote,
                identifier: "tvm.hero",
                spoken: model.spokenHero
            )
        case .failed(let message):
            // Never render a fabricated fallback number: the hero slot carries
            // the explanation instead.
            FailureNotice(
                title: "No rate balances these cash flows",
                detail: message,
                technical: "TVM.SolveError · nothing was appended to the tape",
                identifier: "tvm.hero.failure"
            )
        }
    }

    private func handle(_ key: Keypad.Key) {
        // Entry routing lives in the view model in the real build; the keypad
        // never computes.
        if case .solve = key, let row = model.tapeRow() {
            document.append(row)        // automatic and silent — no save button
        }
    }
}

#Preview("TVM — dark") {
    NavigationStack { TVMScreen(document: .constant(TapeDocument())) }
        .parAppearance()
}

#Preview("TVM — light environment, dark design") {
    // Par is dark-only; this preview proves the design does not depend on the
    // system appearance.
    NavigationStack { TVMScreen(document: .constant(TapeDocument())) }
        .environment(\.colorScheme, .light)
        .parAppearance()
}

#Preview("TVM — AX5") {
    NavigationStack { TVMScreen(document: .constant(TapeDocument())) }
        .environment(\.dynamicTypeSize, .accessibility5)
        .parAppearance()
}
