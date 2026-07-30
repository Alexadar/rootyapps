import SwiftUI
import DimensionKit

/// Spec tab — the CM-Pro glove keypad on a light body with a graphite readout.
/// Digits/Feet/Inch/⁄/ops/=/⌫/C drive the tape; Rise/Run/Diag/Pitch solve in place;
/// Rafter/Stair/Area/Vol open the matching formula screen via the Router.
struct CalcView: View {
    @StateObject private var engine = CalcEngine()
    @EnvironmentObject private var router: Router

    // The precisions the pad offers. Sourced from the Kit that does the rounding, so the chips and
    // `TapeCalcStateSpaceTests`' cross-product can never disagree about which ones ship.
    private var dens: [Int64] { TapeCalc.denominators }

    var body: some View {
        VStack(spacing: 10) {
            readout
            SpecKeypad { handle($0) }
                .frame(maxWidth: .infinity)
        }
        .padding(15)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppBackground())
        .safeAreaInset(edge: .top, spacing: 0) {
            KCGlassTopBar { header }        // 2026 Liquid Glass top bar
        }
        .task { await reelDemoIfNeeded() }
    }

    /// Reel-only: when `KERFCALC_DEMO == "spec"`, self-play the cut-list tape (8'4½" × 3 − 2'6" ÷ 2 =
    /// 11'3¾") on a loop so a screen recording shows the calculator working — the mac reel's Spec scene,
    /// matching the iOS `ReelTour`. No-op otherwise.
    private func reelDemoIfNeeded() async {
        guard LaunchOverride.matches("KERFCALC_DEMO", "spec") else { return }
        let seq: [SpecKeypad.KeyID] = [
            .digit(8), .feet, .digit(4), .inch, .digit(1), .frac, .digit(2),
            .mul, .digit(3), .sub, .digit(2), .feet, .digit(6), .inch, .div, .digit(2), .equals
        ]
        try? await Task.sleep(nanoseconds: 1_000_000_000)      // let the recorder start
        while !Task.isCancelled {
            engine.clear()
            try? await Task.sleep(nanoseconds: 400_000_000)
            for k in seq {
                if Task.isCancelled { return }
                handle(k)
                try? await Task.sleep(nanoseconds: 270_000_000)
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)  // hold the result
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Kerf Calc").font(.system(size: 21, weight: .black)).kerning(-0.4)
                .foregroundStyle(KC.textPrimary)
            RoundedRectangle(cornerRadius: 2).fill(KC.signal).frame(width: 7, height: 7)
            Text("SPEC").font(.system(.caption2, design: .monospaced).weight(.bold)).tracking(1.6)
                .foregroundStyle(KC.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 3)
    }

    private var readout: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(engine.tape.isEmpty ? " " : engine.tape)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(KC.instrumentDim)
                .lineLimit(1).frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityIdentifier("calc.tape")
            Text(engine.display)
                .font(.system(size: 44, weight: .bold, design: .monospaced))
                .foregroundStyle(KC.onInstrument)
                .minimumScaleFactor(0.5).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.18), value: engine.display)
                .accessibilityIdentifier("calc.readout")
            HStack {
                HStack(spacing: 6) {
                    if let rise = engine.rise { register("R", rise) }
                    if let run = engine.run { register("U", run) }
                }
                Spacer()
                HStack(spacing: 5) {
                    ForEach(dens, id: \.self) { d in
                        let on = engine.denominator == d
                        Button { engine.setDenominator(d) } label: {
                            Text("1/\(d)")
                                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .foregroundStyle(on ? KC.signal : KC.instrumentDim)
                                .overlay(RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(on ? KC.signal : Color.white.opacity(0.14), lineWidth: 1))
                                .background(on ? KC.signal.opacity(0.12) : .clear, in: .rect(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("denominator.\(d)")
                    }
                }
            }
        }
        .padding(16)
        .background(KC.instrument, in: .rect(cornerRadius: 22))
        // `.contain`, never `.combine`: combining fuses tape + readout + chips into one element and
        // macOS then synthesises its identifier by joining the children's, so `calc.readout` would
        // not exist at all. iOS happens to keep children addressable, which is what hides it.
        .accessibilityElement(children: .contain)
    }

    private func register(_ tag: String, _ v: String) -> some View {
        Text("\(tag) \(v)")
            .font(.system(.caption2, design: .monospaced).weight(.semibold))
            .foregroundStyle(KC.signal)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(KC.signal.opacity(0.10), in: .rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(KC.signal.opacity(0.25), lineWidth: 1))
    }

    private func handle(_ key: SpecKeypad.KeyID) {
        switch key {
        case .feet: engine.feetKey()
        case .inch: engine.inchKey()
        case .frac: engine.fractionKey()
        case .backspace: engine.backspace()
        case .rise: engine.storeRise()
        case .run: engine.storeRun()
        case .diag: engine.solveDiagonal()
        case .pitch: engine.solvePitch()
        case .rafter: router.open(.rafter)
        case .stair: router.open(.stairs)
        case .area: router.open(.area)
        case .vol: router.open(.volume)
        case .digit(let n): engine.digit(n)
        case .div: engine.setOp(.div)
        case .mul: engine.setOp(.mul)
        case .sub: engine.setOp(.sub)
        case .add: engine.setOp(.add)
        case .clear: engine.clear()
        case .equals: engine.equals()
        }
    }
}
