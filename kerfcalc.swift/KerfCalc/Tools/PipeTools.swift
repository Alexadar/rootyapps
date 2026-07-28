import SwiftUI
import PipeKit
import DimensionKit

private func f(_ x: Double, _ p: Int = 2) -> String { String(format: "%.\(p)f", x) }

// MARK: Simple offset
struct OffsetToolView: View {
    @State private var setIn = 10.0
    @State private var angleIdx = 0
    @State private var customAngle = 60.0
    @State private var availableRunIn = 12.0

    private var angle: Double { PipeFittingChoice.angleDeg(index: angleIdx, custom: customAngle) }

    var body: some View {
        ToolColumns {
            VStack(spacing: 12) {
                CardHeader(title: "Offset", trailing: "fitting multipliers")
                FeetInchField(title: "Set (offset)", value: $setIn, unit: .inch, range: 0...1200)
                SubScreenPicker(titles: PipeFittingChoice.titles, selection: $angleIdx)
                if angleIdx == PipeFittingChoice.otherIndex {
                    NumberField(title: "Fitting angle", value: $customAngle, unit: "°", range: 1...90)
                }
            }.card()

            VStack(spacing: 10) {
                CardHeader(title: "Fit to an available run")
                FeetInchField(title: "Run you have", value: $availableRunIn, unit: .inch, range: 0...1200)
                ResultRow(label: "Angle that fits",
                          value: f(PipeOffset.fittingAngleDeg(setIn: setIn, runIn: availableRunIn)),
                          unit: "°", emphasis: true)
            }.card()
        } outputs: {
            HeroReadout(label: "Travel", value: f(PipeOffset.travelIn(setIn: setIn, fittingAngleDeg: angle)), unit: "in")
                .reelDemo("offset", $setIn, [10, 12, 14, 16, 12])

            VStack(spacing: 10) {
                CardHeader(title: "At \(f(angle, angle == angle.rounded() ? 0 : 2))°")
                ResultRow(label: "Run consumed", value: f(PipeOffset.runIn(setIn: setIn, fittingAngleDeg: angle)), unit: "in")
                ResultRow(label: "Travel multiplier (csc)", value: f(PipeOffset.travelMultiplier(fittingAngleDeg: angle), 4))
                ResultRow(label: "Run multiplier (cot)", value: f(PipeOffset.runMultiplier(fittingAngleDeg: angle), 4))
            }.card()
        }
    }
}

// MARK: Rolling offset
struct RollingOffsetToolView: View {
    @State private var setIn = 6.0
    @State private var rollIn = 8.0
    @State private var angleIdx = 0
    @State private var customAngle = 60.0

    private var angle: Double { PipeFittingChoice.angleDeg(index: angleIdx, custom: customAngle) }
    private var r: RollingOffsetResult { RollingOffset.solve(setIn: setIn, rollIn: rollIn, fittingAngleDeg: angle) }

    var body: some View {
        ToolColumns {
            VStack(spacing: 12) {
                CardHeader(title: "Rolling offset")
                FeetInchField(title: "Set (vertical)", value: $setIn, unit: .inch, range: 0...1200)
                FeetInchField(title: "Roll (horizontal)", value: $rollIn, unit: .inch, range: 0...1200)
                SubScreenPicker(titles: PipeFittingChoice.titles, selection: $angleIdx)
                if angleIdx == PipeFittingChoice.otherIndex {
                    NumberField(title: "Fitting angle", value: $customAngle, unit: "°", range: 1...90)
                }
            }.card()
        } outputs: {
            HeroReadout(label: "Travel", value: f(r.travelIn), unit: "in")
                .reelDemo("rollingOffset", $rollIn, [8, 10, 12, 10])

            VStack(spacing: 10) {
                CardHeader(title: "Layout")
                ResultRow(label: "True offset", value: f(r.trueOffsetIn), unit: "in", emphasis: true)
                ResultRow(label: "Run consumed", value: f(r.runIn), unit: "in")
                ResultRow(label: "Roll the fitting", value: f(r.rollAngleDeg), unit: "°")
                Text("Two angles: the fitting is \(f(angle, 0))°; the roll angle is how far to rotate that plane off vertical.")
                    .font(.caption2).foregroundStyle(KC.textTertiary).frame(maxWidth: .infinity, alignment: .leading)
            }.card()
        }
    }
}

// MARK: Cut length
struct CutLengthToolView: View {
    @State private var centerToCenterIn = 24.0
    @State private var takeoutAIn = 1.5
    @State private var takeoutBIn = 1.5

    private var endToEnd: Double {
        PipeCut.endToEndIn(centerToCenterIn: centerToCenterIn, takeoutAIn: takeoutAIn, takeoutBIn: takeoutBIn)
    }
    private var collides: Bool {
        PipeCut.fittingsCollide(centerToCenterIn: centerToCenterIn, takeoutAIn: takeoutAIn, takeoutBIn: takeoutBIn)
    }

    var body: some View {
        ToolColumns {
            VStack(spacing: 12) {
                CardHeader(title: "Layout", trailing: "your take-outs")
                FeetInchField(title: "Centre to centre", value: $centerToCenterIn, unit: .inch, range: 0...12000)
                FeetInchField(title: "Take-out A", value: $takeoutAIn, unit: .inch, range: 0...240)
                FeetInchField(title: "Take-out B", value: $takeoutBIn, unit: .inch, range: 0...240)
            }.card()
        } outputs: {
            HeroReadout(label: "Cut end to end", value: f(endToEnd), unit: "in")
                .reelDemo("cutLength", $centerToCenterIn, [24, 30, 36, 30])

            VStack(spacing: 10) {
                CardHeader(title: "Check")
                ResultRow(label: "Total take-out", value: f(takeoutAIn + takeoutBIn), unit: "in")
                CheckRow(label: "Fittings fit the dimension", passing: !collides)
                Text("Take-outs vary by manufacturer, material and joint — enter the ones you measured. Not a shipped table.")
                    .font(.caption2).foregroundStyle(KC.textTertiary).frame(maxWidth: .infinity, alignment: .leading)
            }.card()
        }
    }
}

// MARK: Grade / fall
struct GradeToolView: View {
    @State private var runFeet = 40.0
    @State private var gradeIdx = 0
    @State private var customFall = 0.375

    private var fallPerFt: Double { PipeGradeChoice.fallInPerFt(index: gradeIdx, custom: customFall) }

    var body: some View {
        ToolColumns {
            VStack(spacing: 12) {
                CardHeader(title: "Run", trailing: "IPC / UPC")
                FeetInchField(title: "Horizontal run", value: $runFeet, unit: .foot, range: 0...10000)
                SubScreenPicker(titles: PipeGradeChoice.titles, selection: $gradeIdx)
                if gradeIdx == PipeGradeChoice.otherIndex {
                    NumberField(title: "Fall per foot", value: $customFall, unit: "in/ft", range: 0...12)
                }
            }.card()
        } outputs: {
            HeroReadout(label: "Total fall", value: f(PipeGrade.fallIn(runFeet: runFeet, fallInPerFt: fallPerFt)), unit: "in")
                .reelDemo("grade", $runFeet, [40, 60, 80, 60])

            VStack(spacing: 10) {
                CardHeader(title: "Same grade, three ways")
                ResultRow(label: "Percent", value: f(PipeGrade.percent(fallInPerFt: fallPerFt)), unit: "%")
                ResultRow(label: "Ratio", value: "1:\(f(PipeGrade.ratioDenominator(fallInPerFt: fallPerFt), 0))")
                ResultRow(label: "Angle", value: f(PipeGrade.degrees(fallInPerFt: fallPerFt), 3), unit: "°")
            }.card()

            VStack(spacing: 10) {
                CardHeader(title: "Code minimums", trailing: "IPC 704.1 / UPC 708.0")
                CheckRow(label: "≥ ¼\"/ft — drains up to 2½\"", passing: fallPerFt >= 0.25)
                CheckRow(label: "≥ ⅛\"/ft — larger than 2½\"", passing: fallPerFt >= 0.125)
                Text("Minimum slopes are code-cycle values and vary by adopted edition and jurisdiction — confirm against your code.")
                    .font(.caption2).foregroundStyle(KC.textTertiary).frame(maxWidth: .infinity, alignment: .leading)
            }.card()
        }
    }
}
