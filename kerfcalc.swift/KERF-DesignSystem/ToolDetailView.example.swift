import SwiftUI

// Reference for restyling a tool detail (e.g. RafterView): a section-accent screen
// tint, an optional dark diagram card, glove-XL StepperRow inputs, the one HeroReadout,
// a ResultRow list, optional CheckRow code checks, and the FormulaCard.
//
// The composition below is the *shell*. In the app, keep each tool's existing ViewModel
// and its exact set of inputs/outputs — only the presentation is new. Set the accent once:
//   .tint(tool.accent)  +  .background(AppBackground(accent: tool.accent))

/// Regular-size detail (iPad / Mac / iPhone landscape): inputs LEFT, results RIGHT —
/// never a stretched single column. Same cards as the compact layout, regrouped.
struct ToolDetailRegularExample: View {
    @State private var pitch = 6.0
    @State private var run = 12.0
    @State private var spacing = 16.0

    private var perFt: Double { (144 + pitch * pitch).squareRoot() }
    private var line: Double { perFt * run }
    private var plumb: Double { atan2(pitch, 12) * 180 / .pi }
    private var hipPerFt: Double { (288 + pitch * pitch).squareRoot() }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // LEFT — diagram, inputs, formula
            VStack(spacing: 12) {
                RafterDiagram()
                    .frame(height: 150).frame(maxWidth: .infinity)
                    .background(KC.instrument, in: .rect(cornerRadius: KC.rCard))
                VStack(spacing: 0) {
                    StepperRow(title: "Pitch (rise per 12)", value: $pitch, unit: "/12", step: 1, range: 1...24)
                    Divider().overlay(KC.hairline)
                    StepperRow(title: "Run", value: $run, unit: "ft", step: 1, range: 1...80)
                    Divider().overlay(KC.hairline)
                    StepperRow(title: "Rafter spacing", value: $spacing, unit: "in", step: 2, range: 8...24)
                }.card()
                FormulaCard(formula: "Line = Run × √(12² + rise²) ⁄ 12",
                            citation: "NAVEDTRA 14044 · framing-square table")
            }
            // RIGHT — hero, results, hand-off to Spec
            VStack(spacing: 12) {
                HeroReadout(label: "Common line length", value: String(format: "%.2f", line), unit: "in")
                VStack(spacing: 0) {
                    ResultRow(label: "Length per ft of run", value: String(format: "%.2f", perFt), unit: "in")
                    Divider().overlay(KC.hairline)
                    ResultRow(label: "Plumb cut", value: String(format: "%.2f", plumb), unit: "°")
                    Divider().overlay(KC.hairline)
                    ResultRow(label: "Level (seat) cut", value: String(format: "%.2f", 90 - plumb), unit: "°")
                    Divider().overlay(KC.hairline)
                    ResultRow(label: "Hip / valley per ft run", value: String(format: "%.2f", hipPerFt), unit: "in", emphasis: true)
                }.card()
                HStack {
                    Text("Send \(String(format: "%.2f", line))\" to Spec tape")
                        .font(.footnote).foregroundStyle(KC.textSecondary)
                    Spacer()
                    Text("→ SPEC")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(KC.onAccent)
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(KC.signal, in: .rect(cornerRadius: 8))
                }.card()
            }
        }
        .tint(Color(rgbHex: 0x2E6BFF))
    }
}

struct ToolDetailExample: View {
    // Stand-in inputs so the example previews; replace with the RafterViewModel.
    @State private var pitch = 6.0
    @State private var run = 12.0
    @State private var spacing = 16.0

    private var perFt: Double { (144 + pitch * pitch).squareRoot() }
    private var line: Double { perFt * run }
    private var plumb: Double { atan2(pitch, 12) * 180 / .pi }
    private var hipPerFt: Double { (288 + pitch * pitch).squareRoot() }

    var body: some View {
        ScrollView {
            VStack(spacing: 13) {
                RafterDiagram()
                    .frame(height: 150).frame(maxWidth: .infinity)
                    .background(KC.instrument, in: .rect(cornerRadius: KC.rCard))

                VStack(spacing: 0) {
                    StepperRow(title: "Pitch (rise per 12)", value: $pitch, unit: "/12", step: 1, range: 1...24)
                    Divider().overlay(KC.hairline)
                    StepperRow(title: "Run", value: $run, unit: "ft", step: 1, range: 1...80)
                    Divider().overlay(KC.hairline)
                    StepperRow(title: "Rafter spacing", value: $spacing, unit: "in", step: 2, range: 8...24)
                }
                .card()

                HeroReadout(label: "Common line length",
                            value: String(format: "%.2f", line), unit: "in")

                VStack(spacing: 0) {
                    ResultRow(label: "Length per ft of run", value: String(format: "%.2f", perFt), unit: "in")
                    Divider().overlay(KC.hairline)
                    ResultRow(label: "Plumb cut", value: String(format: "%.2f", plumb), unit: "°")
                    Divider().overlay(KC.hairline)
                    ResultRow(label: "Level (seat) cut", value: String(format: "%.2f", 90 - plumb), unit: "°")
                    Divider().overlay(KC.hairline)
                    ResultRow(label: "Hip / valley per ft run", value: String(format: "%.2f", hipPerFt), unit: "in", emphasis: true)
                }
                .card()

                FormulaCard(
                    formula: "Line = Run × √(12² + rise²) ⁄ 12",
                    citation: "NAVEDTRA 14044 · framing-square table",
                    example: "Worked: 6/12 pitch, 12 ft run → 13.42\"/ft × 12 = 161.00\"."
                )
            }
            .padding(16)
        }
        .background(AppBackground(accent: Color(rgbHex: 0x2E6BFF)))  // = ToolSection.framing.accent
        .tint(Color(rgbHex: 0x2E6BFF))
        .navigationTitle("Rafter")
    }
}

/// A clean schematic right-triangle — run, rise, and the rafter in signal.
/// Diagrams are geometry, not decoration; keep them stroke-only on the instrument.
struct RafterDiagram: View {
    var body: some View {
        Canvas { ctx, size in
            let pad: CGFloat = 26
            let a = CGPoint(x: pad, y: size.height - pad)          // bottom-left
            let b = CGPoint(x: size.width - pad, y: size.height - pad) // bottom-right
            let c = CGPoint(x: size.width - pad, y: pad + 6)       // top-right (ridge)

            var run = Path(); run.move(to: a); run.addLine(to: b)
            ctx.stroke(run, with: .color(Color(rgbHex: 0x3A3C43)), lineWidth: 1.5)

            var riseP = Path(); riseP.move(to: b); riseP.addLine(to: c)
            ctx.stroke(riseP, with: .color(Color(rgbHex: 0x6A6C73)), lineWidth: 1.5)

            var raft = Path(); raft.move(to: a); raft.addLine(to: c)
            ctx.stroke(raft, with: .color(Color(rgbHex: 0xE8FB4A)), lineWidth: 2.5)

            let sq = CGRect(x: b.x - 9, y: b.y - 9, width: 9, height: 9)
            ctx.stroke(Path(sq), with: .color(Color(rgbHex: 0x6A6C73)), lineWidth: 1)

            func label(_ s: String, _ p: CGPoint) {
                ctx.draw(Text(s).font(.system(size: 10, design: .monospaced)).foregroundColor(Color(rgbHex: 0x9C9AA2)), at: p)
            }
            label("RUN", CGPoint(x: (a.x + b.x) / 2, y: b.y + 12))
            label("RISE", CGPoint(x: b.x + 14, y: (b.y + c.y) / 2))
            label("RAFTER", CGPoint(x: (a.x + c.x) / 2 - 6, y: (a.y + c.y) / 2 - 12))
        }
    }
}
