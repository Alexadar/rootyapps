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
        // Was `x ? true : true` — always true, so the guard it looks like never fired. At AX3+ in a
        // compact width the five registers and a keypad cannot both fit, and the registers win:
        // they are editable by the system keyboard, so nothing becomes unreachable.
        dynamicTypeSize < .accessibility3 || horizontalSizeClass != .compact
        #endif
    }

    public var body: some View {
        Group {
            // Pinning the answer above the keypad is what keeps it on screen on a phone, where the
            // registers are taller than the space left over. A regular width has room for all of it
            // at once, and the same pinning there opens a hole between the registers and the answer.
            if horizontalSizeClass == .compact {
                compactColumn
            } else {
                regularColumn
            }
        }
        .background(Par.Palette.base)
        .navigationTitle("Time Value of Money")
        // The keypad's Solve key appends on iOS; the Mac has no keypad, so the toolbar carries the
        // same action. Without it a Mac solve could never reach the tape.
    }

    private var compactColumn: some View {
        VStack(spacing: 0) {
            ScrollView { inputs.padding(.bottom, 12) }

            hero
                .padding(.horizontal, Par.Metrics.gutter)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .background(Par.Palette.base)
                // A hairline above the pinned answer, so content scrolling under it reads as
                // scrolling under something rather than as being cut off.
                .overlay(alignment: .top) {
                    Rectangle().fill(Par.Palette.separator).frame(height: 0.5)
                }

            if showsKeypad { keypad }
        }
    }

    /// Everything in one scroll, top-aligned: the slack falls below the keypad, where it reads as
    /// room rather than as a gap. It still scrolls, which is what an accessibility text size needs.
    private var regularColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                inputs
                hero.padding(.horizontal, Par.Metrics.gutter)
                if showsKeypad { keypad }
            }
            .padding(.bottom, 12)
        }
    }

    private var inputs: some View {
        VStack(alignment: .leading, spacing: 12) {
            solveTargetPicker
            registers
            frequencies
            AppendToTapeBar(label: $model.rowLabel, canAppend: model.tapeRow() != nil,
                            identifier: "tvm.tape") { append() }
            ProvenanceStrip(
                authorities: ["31 CFR 356 App B §II.A", "12 CFR 1030 App A"],
                conventions: model.conventions,
                identifier: "tvm.provenance"
            )
        }
        .padding(.horizontal, Par.Metrics.gutter)
    }

    /// Which of the five is the answer. A visible picker is also the answer to "how would anyone
    /// know they could do that" — it needs no coach mark because it is simply on screen.
    private var solveTargetPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Solve for")
                .font(.caption)
                .foregroundStyle(Par.Palette.labelSecondary)
            SubScreenPicker(
                options: [(TVM.Variable.periods, "n"), (.ratePct, "i%"), (.presentValue, "PV"),
                          (.payment, "PMT"), (.futureValue, "FV")],
                selection: Binding(get: { model.solveFor }, set: { model.solve(for: $0) }),
                identifier: "tvm.solveFor"
            )
        }
    }

    private var keypad: some View {
        Keypad(solveTargetName: model.solveTargetSymbol, columns: keypadColumns) { key in
            handle(key)
        }
    }

    private func append() {
        if let row = model.tapeRow() { document.append(row) }
    }

    private var registers: some View {
        VStack(spacing: 0) {
            register(.periods, "n", "periods", "months", $model.periods, digits: 0,
                     identifier: "tvm.input.periods")
            Divider().overlay(Par.Palette.separator)
            register(.ratePct, "i%", "annual rate", "nominal", $model.annualRatePct, digits: 3,
                     identifier: "tvm.input.annualRate")
            Divider().overlay(Par.Palette.separator)
            register(.presentValue, "PV", "present value", "USD", $model.presentValue,
                     identifier: "tvm.input.presentValue")
            Divider().overlay(Par.Palette.separator)
            register(.payment, "PMT", "payment", "USD", $model.payment,
                     identifier: "tvm.input.payment")
            Divider().overlay(Par.Palette.separator)
            register(.futureValue, "FV", "future value", "USD", $model.futureValue,
                     identifier: "tvm.input.futureValue")
        }
        .glassCard()
    }

    /// One register row: the field itself, plus an amber ring when the keypad is aimed at it.
    /// Tapping the row selects it — which is how a keypad-driven calculator is meant to work, and
    /// what keeps the iOS system keyboard off screen.
    @ViewBuilder
    private func register(_ variable: TVM.Variable, _ symbol: String, _ caption: String,
                          _ unit: String, _ value: Binding<Double>, digits: Int = 2,
                          identifier: String) -> some View {
        NumberField(symbol, caption: caption, unit: unit, value: value,
                    range: model.range(for: variable), digits: digits,
                    isSolveTarget: model.solveFor == variable,
                    isKeypadDriven: showsKeypad,
                    pendingEntry: model.entryTarget == variable ? model.entryBuffer : nil,
                    identifier: identifier)
            .contentShape(Rectangle())
            .onTapGesture { model.select(variable) }
            .overlay(alignment: .leading) {
                if model.entryTarget == variable && model.solveFor != variable {
                    Rectangle().fill(Par.Palette.accent).frame(width: 2.5)
                }
            }
            .accessibilityIdentifier("\(identifier).row")
            .accessibilityAddTraits(showsKeypad ? .isButton : [])
    }

    private var frequencies: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { frequencyCards }
            VStack(spacing: 8) { frequencyCards }
        }
    }

    /// P/YR, C/YR and BEG/END.
    ///
    /// These were `ResultRow`s — display-only cards, styled exactly like the editable registers above
    /// them, bound to properties nothing in the app ever assigned. `TVMKit` has always supported every
    /// value of all three, so an annuity-due and a quarterly instrument were computable by the Kit and
    /// unreachable from the screen. A lease is an annuity-due; a quarterly bond is not monthly.
    @ViewBuilder
    private var frequencyCards: some View {
        SettingCard("payments / yr", value: String(model.paymentsPerYear),
                    identifier: "tvm.paymentsPerYear",
                    spoken: "payments per year, \(model.paymentsPerYear)") {
            Frequency.picker("payments / yr", selection: $model.paymentsPerYear)
        }
        SettingCard("compounds / yr", value: String(model.compoundsPerYear),
                    identifier: "tvm.compoundsPerYear",
                    spoken: "compounding periods per year, \(model.compoundsPerYear)") {
            Frequency.picker("compounds / yr", selection: $model.compoundsPerYear)
        }
        SettingCard("timing", value: model.timing == .end ? "End" : "Begin",
                    identifier: "tvm.timing",
                    spoken: model.timing == .end
                        ? "payments at end of period" : "payments at beginning of period") {
            Picker("timing", selection: $model.timing) {
                Text("End of period").tag(TVM.Timing.end)
                Text("Beginning of period").tag(TVM.Timing.begin)
            }
            .pickerStyle(.inline)
        }
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

    /// The keypad never computes: it edits the selected register, and the view model recomputes.
    private func handle(_ key: Keypad.Key) {
        switch key {
        case .digit(let value): model.digit(value)
        case .decimal: model.decimalPoint()
        case .sign: model.toggleSign()
        case .backspace: model.backspace()
        case .clearEntry: model.clearEntry()
        case .solve:
            if let row = model.tapeRow() {
                document.append(row)    // automatic and silent — no save button
                model.rowLabel = ""
            }
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
