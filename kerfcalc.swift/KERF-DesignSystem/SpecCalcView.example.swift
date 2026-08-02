import SwiftUI

// Reference for restyling CalcView.swift — the Spec tab, CM-Pro hard keys, glove-XL.
// The dark readout carries a faint tape line, the big ft-in-frac result, stored
// Rise/Run registers, and the precision pills. Below it, the `SpecKeypad` layout.
//
// This example drives a placeholder display string so it previews on its own; in
// the app, replace the local @State with the existing `CalcEngine` and route
// `SpecKeypad`'s KeyID into it (feet/inch/frac/op/equals, and rafter/stair/area/vol
// push a formula via the navigation path).

struct SpecCalcExample: View {
    @State private var tape = "6' 2 1/2\"  +  2' 7 3/4\""
    @State private var display = "8' 10 1/4\""
    @State private var den = 16
    @State private var rise: String? = nil
    @State private var run: String? = nil

    private let dens = [8, 16, 32]

    var body: some View {
        VStack(spacing: 10) {
            header
            readout
            SpecKeypad { key in
                // route into CalcEngine; nav keys push a Tool onto the path
                _ = key
            }
            .frame(maxWidth: .infinity)
        }
        .padding(15)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppBackground())
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("KERF").font(.system(size: 21, weight: .black)).kerning(-0.4)
            RoundedRectangle(cornerRadius: 2).fill(KC.signal).frame(width: 7, height: 7)
            Text("SPEC").font(.system(.caption2, design: .monospaced).weight(.bold)).tracking(1.6)
                .foregroundStyle(KC.textTertiary)
            Spacer()
            Image(systemName: "gearshape").foregroundStyle(KC.textSecondary)
        }
        .padding(.horizontal, 3)
    }

    private var readout: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(tape.isEmpty ? " " : tape)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(KC.instrumentDim)
                .lineLimit(1).frame(maxWidth: .infinity, alignment: .trailing)
            Text(display)
                .font(.system(size: 44, weight: .bold, design: .monospaced))
                .foregroundStyle(KC.onInstrument)
                .minimumScaleFactor(0.5).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentTransition(.numericText())
            HStack {
                HStack(spacing: 6) {
                    if let rise { register("R", rise) }
                    if let run  { register("U", run) }
                }
                Spacer()
                HStack(spacing: 5) {
                    ForEach(dens, id: \.self) { d in
                        let on = den == d
                        Button { den = d } label: {
                            Text("1/\(d)")
                                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .foregroundStyle(on ? KC.signal : KC.instrumentDim)
                                .overlay(RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(on ? KC.signal : Color.white.opacity(0.14), lineWidth: 1))
                                .background(on ? KC.signal.opacity(0.12) : .clear, in: .rect(cornerRadius: 7))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(KC.instrument, in: .rect(cornerRadius: 22))
    }

    private func register(_ tag: String, _ v: String) -> some View {
        Text("\(tag) \(v)")
            .font(.system(.caption2, design: .monospaced).weight(.semibold))
            .foregroundStyle(KC.signal)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(KC.signal.opacity(0.10), in: .rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(KC.signal.opacity(0.25), lineWidth: 1))
    }
}
