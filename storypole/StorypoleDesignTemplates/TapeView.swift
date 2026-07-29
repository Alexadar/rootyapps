import SwiftUI
import DimensionKit

/// The tape measure graphic — *"No need to guess where to place your mark."*
///
/// **Takes no arithmetic decisions of its own.** Where the cursor sits comes from
/// `Tape.position(of:)`; the value string is formatted by the Kit and passed in. This view only
/// decides geometry — how tall a tick is and where the label goes.
///
/// - **Defect ②** — a graphic that showed the wrong result. Position is unit tested before any
///   pixel is drawn.
/// - **Defect ④** — the blade is labelled in **feet and inches**, never a running inch count, and
///   when `Tape.smallest(for:)` returns `nil` nothing is drawn. There is no fallback that stretches
///   a tape past reality.
struct TapeView: View {
    let value: FeetInch
    var denominator: Int64 = 16

    private var tape: Tape? { Tape.smallest(for: value) }

    var body: some View {
        VStack(alignment: .leading, spacing: SP.s2) {
            if let tape, let position = tape.position(of: value) {
                blade(tape: tape, position: position)
                HStack {
                    Text("(String(tape.lengthFeet)) ft tape")
                        .accessibilityIdentifier("tape.blade")
                    Spacer()
                    Text(tape.length.formatted(toDenominator: 1))
                }
                .font(SPType.footnote)
                .foregroundStyle(SP.textTertiary)
            } else {
                noTape
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Tape measure"))
        .accessibilityValue(Text(value.formatted(toDenominator: denominator)))
    }

    // MARK: - The blade

    private static let bladeHeight: CGFloat = 76

    private func blade(tape: Tape, position: Double) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let inches = tape.length.inchesValue
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: [SP.tapeBody, SP.tapeBodyLo],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(SP.tapeEdge, lineWidth: 1)
                    )

                // Graduation hierarchy, drawn in one pass: 1/2 ft short, 1 ft tall, labelled feet.
                // Pure geometry — no measurement arithmetic happens here.
                Canvas { ctx, size in
                    let step = labelStep(tape: tape)
                    for half in 0...(tape.lengthFeet * 2) {
                        let x = size.width * (Double(half) * 6 / inches)
                        let isFoot = half % 2 == 0
                        let h: CGFloat = isFoot ? 20 : 11
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: h))
                        ctx.stroke(p, with: .color(SP.tapeMark.opacity(isFoot ? 0.75 : 0.35)),
                                   lineWidth: isFoot ? 1.5 : 1)

                        let foot = half / 2
                        if isFoot, foot % step == 0 {
                            let label = Text(foot == 0 ? "0" : "(String(foot))'")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(SP.tapeMark.opacity(0.85))
                            ctx.draw(label, at: CGPoint(x: min(x + 4, size.width - 12), y: 30),
                                     anchor: .topLeading)
                        }
                    }
                }
                .frame(height: Self.bladeHeight)

                // The cursor: a flag you can see across a garage. Position is Tape.position(of:).
                let cx = w * position
                Path { p in
                    p.move(to: CGPoint(x: cx, y: 0))
                    p.addLine(to: CGPoint(x: cx, y: Self.bladeHeight))
                }
                .stroke(SP.tapeCursor, lineWidth: 2.5)
                Circle()
                    .fill(SP.tapeCursor)
                    .frame(width: 9, height: 9)
                    .position(x: cx, y: 4.5)

                // The hook, at true zero.
                RoundedRectangle(cornerRadius: 2)
                    .fill(SP.tapeHook)
                    .frame(width: 5, height: Self.bladeHeight)
            }
        }
        .frame(height: Self.bladeHeight)
    }

    /// Thin the foot labels so they never collide on a long blade.
    private func labelStep(tape: Tape) -> Int {
        tape.lengthFeet > 16 ? 5 : (tape.lengthFeet > 12 ? 2 : 1)
    }

    // MARK: - The refusal

    /// `Tape.smallest(for:)` returned nil. The number stands alone; nothing is drawn.
    private var noTape: some View {
        HStack(spacing: SP.s3) {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(SP.textTertiary, lineWidth: 1.5)
                .frame(width: 26, height: 14)
            Text(value.isNegative
                 ? "A tape has no negative side."
                 : "Longer than any real tape — no blade to draw.")
                .font(SPType.label)
                .foregroundStyle(SP.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, SP.s3)
        .accessibilityIdentifier("tape.none")
    }
}

#Preview("On the blade") {
    VStack(spacing: SP.s5) {
        TapeView(value: FeetInch(feet: 8, inches: 10, num: 1, den: 4))
        TapeView(value: FeetInch(feet: 22))
        TapeView(value: FeetInch(feet: 40))          // no real tape — draws nothing
    }
    .padding()
    .background(SP.background)
}

#Preview("Dark") {
    VStack(spacing: SP.s5) {
        TapeView(value: FeetInch(feet: 8, inches: 10, num: 1, den: 4))
        TapeView(value: FeetInch(feet: 22))
    }
    .padding()
    .background(SP.background)
    .preferredColorScheme(.dark)
}
