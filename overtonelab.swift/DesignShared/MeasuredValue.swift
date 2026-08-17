import SwiftUI

/// Marks a value as measured with **three redundant signals, none of them colour**: a waveform glyph,
/// a dotted underline, and the word *Measured* in the caption.
///
/// Three, because each one fails for someone. Colour alone fails for the colour-blind and in
/// grayscale; a glyph alone fails with images off; a word alone is easy to miss beside a big number.
/// Provenance also rides in `accessibilityValue` rather than a decorative image, so VoiceOver says
/// "0.81, measured" instead of announcing an icon nobody asked about.
///
/// Editing clears all three instantly — there is no "measured but modified".
struct MeasuredValue<Content: View>: View {
    let provenance: Provenance
    let label: LocalizedStringKey
    let spokenValue: String
    @ViewBuilder var content: Content

    init(provenance: Provenance, label: LocalizedStringKey, spokenValue: String,
                @ViewBuilder content: () -> Content) {
        self.provenance = provenance; self.label = label
        self.spokenValue = spokenValue; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if provenance.isMeasured {
                    Image(systemName: "waveform")                 // 1 — shape
                        .font(.system(size: 9))
                        .foregroundStyle(OTL.textSecondary)
                        .accessibilityHidden(true)                // spoken via value, not image
                }
                // A branch, not a ternary: the two arms are String and Text, which do not unify.
                // Both halves stay localisable — "Measured" is its own key, so a translator never has
                // to reproduce the separator.
                Group {
                    if provenance.isMeasured {
                        Text("\(Text(label)) · \(Text("Measured"))")   // 2 — words, localised
                    } else {
                        Text(label)
                    }
                }
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(OTL.textSecondary)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            }
            content
                .overlay(alignment: .bottom) {
                    if provenance.isMeasured {                    // 3 — texture
                        DottedRule()
                            .stroke(style: .init(lineWidth: 2, dash: [2, 3]))
                            .foregroundStyle(Color.white.opacity(0.45))
                            .frame(height: 2)
                            .offset(y: 3)
                    }
                }
            if case .measured(let source, let at) = provenance {
                Text("\(source) · \(at.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(OTL.textTertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(provenance.isMeasured ? "\(spokenValue), measured" : spokenValue))
    }
}

struct DottedRule: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: 0, y: r.midY))
        p.addLine(to: .init(x: r.maxX, y: r.midY))
        return p
    }
}
