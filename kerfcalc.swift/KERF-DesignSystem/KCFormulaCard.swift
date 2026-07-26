import SwiftUI

/// The differentiator, made visible: every formula screen shows the *actual formula*
/// and the code / standard it cites, on the dark instrument surface. The green
/// "VERIFIED" badge maps to the oracle-backed test that guards this calc.
///
/// This is presentation only — the number still comes from the `*Kit` package.
struct FormulaCard: View {
    /// The formula, written for a monospaced line (e.g. "Line = Run × √(12² + rise²) ⁄ 12").
    let formula: String
    /// The cited source (e.g. "NAVEDTRA 14044 · framing-square table").
    let citation: String
    /// Optional worked example line.
    var example: String? = nil
    /// Whether an oracle-backed test covers this calc (drives the VERIFIED badge).
    var verified: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("ƒ").font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(KC.signal)
                Text("FORMULA")
                    .font(.system(.caption2, design: .monospaced).weight(.semibold)).tracking(1.4)
                    .foregroundStyle(KC.instrumentDim)
            }

            Text(formula)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(KC.onInstrument)
                .padding(.horizontal, 14).padding(.vertical, 13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(rgbHex: 0x0F1013), in: .rect(cornerRadius: 12))

            HStack(spacing: 7) {
                if verified {
                    Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(KC.ok)
                    Text("VERIFIED")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(KC.ok)
                    Text("·").foregroundStyle(KC.instrumentDim)
                }
                Text(citation)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color(rgbHex: 0x9C9AA2))
                    .lineLimit(2)
            }

            if let example {
                Text(example)
                    .font(.footnote)
                    .foregroundStyle(Color(rgbHex: 0xB4B2B8))
                    .padding(.top, 11)
                    .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KC.instrument, in: .rect(cornerRadius: KC.rCard))
    }
}
