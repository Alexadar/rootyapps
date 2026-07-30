import SwiftUI
import FramingKit
import DimensionKit

private func f(_ x: Double, _ p: Int = 2) -> String { String(format: "%.\(p)f", x) }

// MARK: Rafter
struct RafterToolView: View {
    @State private var rise = 6.0      // X-in-12
    @State private var runFt = 12.0
    @State private var spacing = 16.0  // o.c. inches
    @State private var ridge = 1.5     // ridge board thickness, inches
    @State private var overhang = 12.0 // horizontal overhang, inches

    var body: some View {
        ToolColumns {
            RafterDiagram()
                .frame(height: 140).frame(maxWidth: .infinity)
                .background(KC.instrument, in: .rect(cornerRadius: KC.rCard))

            VStack(spacing: 0) {
                StepperRow(title: "Pitch (rise per 12)", value: $rise, unit: "/12", step: 1, range: 1...24,
                           identifier: "input.rafter.pitch")
                Divider().overlay(KC.hairline)
                FeetInchField(title: "Run", value: $runFt, unit: .foot, range: 1...80,
                              identifier: "input.rafter.run")
                Divider().overlay(KC.hairline)
                StepperRow(title: "Rafter spacing", value: $spacing, unit: "in", step: 2, range: 8...24,
                           identifier: "input.rafter.spacing")
                Divider().overlay(KC.hairline)
                FeetInchField(title: "Ridge thickness", value: $ridge, unit: .inch, range: 0...6)
                Divider().overlay(KC.hairline)
                FeetInchField(title: "Overhang", value: $overhang, unit: .inch, range: 0...60)
            }.card()
        } outputs: {
            HeroReadout(label: "Actual cut length",
                        value: f(Rafter.actualLength(rise: rise, runFeet: runFt, ridgeThicknessIn: ridge, overhangIn: overhang)),
                        unit: "in", identifier: "rafter.hero")
                .reelDemo("rafter", $rise, [6, 7, 8, 9, 10, 9, 8, 7])

            VStack(spacing: 10) {
                CardHeader(title: "Common rafter")
                ResultRow(label: "Line length (to ridge ℄)", value: f(Rafter.commonLength(rise: rise, runFeet: runFt)), unit: "in")
                ResultRow(label: "− ½ ridge deduction", value: f(Rafter.ridgeDeductionIn(rise: rise, ridgeThicknessIn: ridge)), unit: "in")
                ResultRow(label: "+ overhang (tail)", value: f(Rafter.overhangAlongIn(rise: rise, overhangIn: overhang)), unit: "in")
                ResultRow(label: "Length per ft of run", value: f(Rafter.commonPerFootRun(rise: rise)), unit: "in")
                ResultRow(label: "Plumb cut", value: f(Rafter.plumbCutDegrees(rise: rise)), unit: "°")
                ResultRow(label: "Level (seat) cut", value: f(Rafter.levelCutDegrees(rise: rise)), unit: "°")
            }.card()

            VStack(spacing: 10) {
                CardHeader(title: "Hip / valley & jacks")
                ResultRow(label: "Hip/valley per ft run", value: f(Rafter.hipValleyPerFootRun(rise: rise)), unit: "in")
                ResultRow(label: "Hip/valley line length", value: f(Rafter.hipValleyLength(rise: rise, commonRunFeet: runFt)), unit: "in")
                ResultRow(label: "Jack common difference", value: f(Rafter.jackCommonDifference(rise: rise, spacingInches: spacing)), unit: "in")
            }.card()
        }
    }
}

/// Clean schematic right-triangle — run, rise, and the rafter in signal.
struct RafterDiagram: View {
    var body: some View {
        Canvas { ctx, size in
            let pad: CGFloat = 26
            let a = CGPoint(x: pad, y: size.height - pad)
            let b = CGPoint(x: size.width - pad, y: size.height - pad)
            let c = CGPoint(x: size.width - pad, y: pad + 6)
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

// MARK: Stairs
struct StairsToolView: View {
    @State private var totalRise = 108.0
    @State private var tread = 10.0
    @State private var idealRiser = 7.5
    @State private var headroom = 84.0
    @State private var codeIdx = 0
    private var code: StairCode { StairCodeChoice.code(index: codeIdx) }
    private var r: StairResult { Stairs.solve(totalRise: totalRise, treadDepth: tread, idealRiser: idealRiser, code: code, headroomIn: headroom) }

    var body: some View {
        ToolColumns {
            StairsDiagram()
                .frame(height: 130).frame(maxWidth: .infinity)
                .background(KC.instrument, in: .rect(cornerRadius: KC.rCard))

            VStack(spacing: 12) {
                CardHeader(title: "Stair", trailing: code.name)
                SubScreenPicker(titles: StairCodeChoice.titles, selection: $codeIdx, identifier: "stairs.code")
                FeetInchField(title: "Total rise (floor-floor)", value: $totalRise, unit: .inch, range: 1...400)
                NumberField(title: "Tread depth", value: $tread, unit: "in", range: 1...24)
                NumberField(title: "Target riser", value: $idealRiser, unit: "in", range: 4...12)
                FeetInchField(title: "Headroom (measured)", value: $headroom, unit: .inch, range: 0...200)
            }.card()
        } outputs: {
            HeroReadout(label: "Risers", value: "\(r.risers)", unit: "@ \(f(r.riserHeight))\"", identifier: "stairs.hero")
                .reelDemo("stairs", $totalRise, [96, 108, 116, 120, 108])

            VStack(spacing: 10) {
                CardHeader(title: "Layout")
                ResultRow(label: "Riser height", value: f(r.riserHeight), unit: "in", tone: r.riserOK ? KC.ok : KC.warn)
                ResultRow(label: "Treads", value: "\(r.treads)")
                ResultRow(label: "Total run", value: f(r.totalRun), unit: "in")
                ResultRow(label: "Stringer length", value: f(r.stringerLength), unit: "in")
            }.card()

            VStack(spacing: 10) {
                CardHeader(title: "Code checks", trailing: code.name)
                CheckRow(label: "Riser ≤ \(f(code.maxRiser))\"", passing: r.riserOK)
                CheckRow(label: "Tread ≥ \(f(code.minTread))\"", passing: r.treadOK)
                CheckRow(label: "Headroom ≥ 6'8\"", passing: r.headroomOK)
                ResultRow(label: "Blondel 2R+T (≈24–25)", value: f(r.blondel), unit: "in")
            }.card()
        }
    }
}

/// A clean side-profile of a stair flight — treads/risers in signal, stringer faint.
struct StairsDiagram: View {
    var body: some View {
        Canvas { ctx, size in
            let pad: CGFloat = 26
            let steps = 4
            let x0 = pad, y0 = size.height - pad
            let sw = (size.width - 2 * pad) / CGFloat(steps)
            let sh = (size.height - 2 * pad) / CGFloat(steps)
            var path = Path(); path.move(to: CGPoint(x: x0, y: y0))
            var x = x0, y = y0
            for _ in 0..<steps {
                x += sw; path.addLine(to: CGPoint(x: x, y: y))     // tread
                y -= sh; path.addLine(to: CGPoint(x: x, y: y))     // riser
            }
            var stringer = Path(); stringer.move(to: CGPoint(x: x0, y: y0)); stringer.addLine(to: CGPoint(x: x, y: y))
            ctx.stroke(stringer, with: .color(Color(rgbHex: 0x6A6C73)), lineWidth: 1.5)
            ctx.stroke(path, with: .color(Color(rgbHex: 0xE8FB4A)), lineWidth: 2.5)
            func label(_ t: String, _ p: CGPoint) {
                ctx.draw(Text(t).font(.system(size: 10, design: .monospaced)).foregroundColor(Color(rgbHex: 0x9C9AA2)), at: p)
            }
            label("RISE", CGPoint(x: x0 + sw + 16, y: y0 - sh / 2))
            label("RUN", CGPoint(x: x0 + sw / 2, y: y0 + 12))
            label("STRINGER", CGPoint(x: (x0 + x) / 2 + 4, y: (y0 + y) / 2 - 12))
        }
    }
}

// MARK: Right angle / pitch
struct PitchToolView: View {
    @State private var rise = 4.0
    @State private var run = 12.0
    var body: some View {
        ToolColumns {
            VStack(spacing: 12) {
                CardHeader(title: "Right triangle")
                NumberField(title: "Rise", value: $rise, range: 0...1000)
                NumberField(title: "Run", value: $run, range: 0...1000)
            }.card()
        } outputs: {
            HeroReadout(label: "Diagonal (hypotenuse)", value: f(Pitch.diagonal(rise: rise, run: run), 3), identifier: "pitch.hero")

            VStack(spacing: 10) {
                CardHeader(title: "Solved")
                ResultRow(label: "Angle", value: f(Pitch.angleDegrees(rise: rise, run: run)), unit: "°")
                ResultRow(label: "Slope", value: f(Pitch.slopePercent(rise: rise, run: run)), unit: "%")
                ResultRow(label: "Pitch (rise-in-12)", value: f(Pitch.riseInTwelve(rise: rise, run: run)), unit: "/12")
            }.card()
        }
    }
}
