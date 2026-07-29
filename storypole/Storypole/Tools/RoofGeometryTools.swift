import SwiftUI
import DimensionKit
import PitchKit
import GeometryKit

// MARK: - Roof pitch — three ways, because three trades read it three ways

struct RoofPitchToolView: View {
    @State private var riseIn12 = 6.0

    var body: some View {
        VStack(alignment: .leading, spacing: SP.s3) {
            NumberField(label: "Rise in 12", value: $riseIn12, unit: "in", range: 0...36,
                        identifier: "pitch.rise")

            VStack(spacing: SP.s3) {
                ResultRow(label: "Pitch", value: Fmt.trim(riseIn12) + " / 12", emphasis: true,
                          identifier: "pitch.ratio")
                ResultRow(label: "Angle", value: Fmt.deg(Pitch.angleFromPitch(riseIn12: riseIn12)),
                          identifier: "pitch.angle")
                ResultRow(label: "Slope", value: Fmt.pct(Pitch.slopePercent(rise: riseIn12, run: 12)),
                          identifier: "pitch.percent")
                ResultRow(label: "Pitch multiplier", value: Fmt.f(Pitch.pitchMultiplier(riseIn12: riseIn12), 6),
                          identifier: "pitch.multiplier")
            }
            .spCard()

            Text("Roofers, framers and inspectors each use a different one of these three.")
                .font(SPType.footnote).foregroundStyle(SP.textTertiary)
        }
    }
}

// MARK: - Rafter

struct RafterToolView: View {
    @State private var riseIn12 = 6.0
    @State private var runFeet = 12.0
    @State private var ridgeIn = 1.5
    @State private var overhangIn = 12.0
    @State private var spacingIn = 16.0
    @State private var denominator: Int64 = 16

    var body: some View {
        VStack(alignment: .leading, spacing: SP.s3) {
            NumberField(label: "Rise in 12", value: $riseIn12, unit: "in", range: 0.5...36,
                        identifier: "rafter.rise")
            NumberField(label: "Run", value: $runFeet, unit: "ft", range: 0...200,
                        identifier: "rafter.run")
            NumberField(label: "Ridge thickness", value: $ridgeIn, unit: "in", range: 0...12,
                        identifier: "rafter.ridge")
            NumberField(label: "Overhang", value: $overhangIn, unit: "in", range: 0...96,
                        identifier: "rafter.overhang")
            NumberField(label: "Jack spacing", value: $spacingIn, unit: "in", range: 1...48,
                        identifier: "rafter.spacing")

            let actual = Rafter.actualLength(rise: riseIn12, runFeet: runFeet,
                                             ridgeThicknessIn: ridgeIn, overhangIn: overhangIn)
            VStack(spacing: SP.s3) {
                ResultRow(label: "Actual cut length",
                          value: FeetInch.approx(inches: actual, den: denominator).formatted(toDenominator: denominator),
                          emphasis: true, identifier: "rafter.actual")
                ResultRow(label: "Line length",
                          value: FeetInch.approx(inches: Rafter.commonLength(rise: riseIn12, runFeet: runFeet),
                                                 den: denominator).formatted(toDenominator: denominator),
                          identifier: "rafter.line")
                ResultRow(label: "Per foot of run", value: Fmt.f(Rafter.commonPerFootRun(rise: riseIn12), 2),
                          unit: "in", identifier: "rafter.perFoot")
                ResultRow(label: "Hip / valley per foot", value: Fmt.f(Rafter.hipValleyPerFootRun(rise: riseIn12), 2),
                          unit: "in", identifier: "rafter.hip")
                ResultRow(label: "Plumb cut", value: Fmt.deg(Rafter.plumbCutDegrees(rise: riseIn12)),
                          identifier: "rafter.plumb")
                ResultRow(label: "Level cut", value: Fmt.deg(Rafter.levelCutDegrees(rise: riseIn12)),
                          identifier: "rafter.level")
                ResultRow(label: "Jack common difference",
                          value: FeetInch.approx(inches: Rafter.jackCommonDifference(rise: riseIn12, spacingInches: spacingIn),
                                                 den: denominator).formatted(toDenominator: denominator),
                          identifier: "rafter.jackDiff")
            }
            .spCard()
            DenominatorPicker(denominator: $denominator)
        }
    }
}

// MARK: - Square up

struct DiagonalToolView: View {
    @State private var aText = "12'"
    @State private var bText = "16'"
    @State private var measuredText = ""
    @State private var denominator: Int64 = 16

    var body: some View {
        VStack(alignment: .leading, spacing: SP.s3) {
            DimensionField(label: "Side A", text: $aText, identifier: "diag.a")
            DimensionField(label: "Side B", text: $bText, identifier: "diag.b")

            if let a = FeetInch.parse(aText), let b = FeetInch.parse(bText) {
                let d = Diagonal.hypotenuse(a.inchesValue, b.inchesValue)
                VStack(spacing: SP.s3) {
                    ResultRow(label: "True diagonal",
                              value: FeetInch.approx(inches: d, den: denominator).formatted(toDenominator: denominator),
                              emphasis: true, identifier: "diag.result")
                    ResultRow(label: "Decimal inches", value: Fmt.f(d, 4), unit: "in",
                              identifier: "diag.decimal")
                }
                .spCard()

                DimensionField(label: "Measured diagonal (optional)", text: $measuredText,
                               placeholder: "20'", identifier: "diag.measured")
                if let m = FeetInch.parse(measuredText) {
                    let off = Diagonal.outOfSquare(length: a.inchesValue, width: b.inchesValue,
                                                   measuredDiagonal: m.inchesValue)
                    VStack(spacing: SP.s3) {
                        ResultRow(label: abs(off) < 1e-9 ? "Square" : (off > 0 ? "Long by" : "Short by"),
                                  value: FeetInch.approx(inches: abs(off), den: denominator)
                                      .formatted(toDenominator: denominator),
                                  emphasis: true, identifier: "diag.outOfSquare")
                    }
                    .spCard()
                }
            }

            Text("A 3-4-5 triangle is square: 3' and 4' give exactly 5'.")
                .font(SPType.footnote).foregroundStyle(SP.textTertiary)
        }
    }
}

// MARK: - Miter & bevel

struct MiterToolView: View {
    @State private var corner = 90.0
    @State private var sides = 4
    @State private var spring = 38.0
    @State private var compound = false

    var body: some View {
        VStack(alignment: .leading, spacing: SP.s3) {
            Toggle("Crown (compound)", isOn: $compound)
                .font(SPType.label)
                .accessibilityIdentifier("miter.compound")

            if compound {
                NumberField(label: "Spring angle", value: $spring, unit: "°", range: 1...89,
                            identifier: "miter.spring")
                Stepper("Sides: \(sides)", value: $sides, in: 3...24)
                    .font(SPType.label).accessibilityIdentifier("miter.sides")
                let s = Miter.compound(springDeg: spring, sides: sides)
                VStack(spacing: SP.s3) {
                    ResultRow(label: "Miter", value: Fmt.deg(s.miter), emphasis: true,
                              identifier: "miter.result")
                    ResultRow(label: "Bevel", value: Fmt.deg(s.bevel), identifier: "miter.bevel")
                }
                .spCard()
                Text("Published crown tables: 38° spring → 31.62° / 33.86°; 45° → 35.26° / 30.00°.")
                    .font(SPType.footnote).foregroundStyle(SP.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                NumberField(label: "Measured corner", value: $corner, unit: "°", range: 1...179,
                            identifier: "miter.corner")
                Stepper("Frame sides: \(sides)", value: $sides, in: 3...24)
                    .font(SPType.label).accessibilityIdentifier("miter.sides")
                VStack(spacing: SP.s3) {
                    ResultRow(label: "Miter for this corner", value: Fmt.deg(Miter.forCornerDeg(corner)),
                              emphasis: true, identifier: "miter.result")
                    ResultRow(label: "Regular \(sides)-sided frame", value: Fmt.deg(Miter.simpleDeg(sides: sides)),
                              identifier: "miter.frame")
                }
                .spCard()
            }
        }
    }
}

// MARK: - Circle & pipe wrap

struct CircleToolView: View {
    @State private var dText = "4\""
    @State private var angle = 90.0
    @State private var denominator: Int64 = 16

    var body: some View {
        VStack(alignment: .leading, spacing: SP.s3) {
            DimensionField(label: "Diameter", text: $dText, placeholder: "4\"", identifier: "circle.d")
            NumberField(label: "Arc angle", value: $angle, unit: "°", range: 0...360,
                        identifier: "circle.angle")

            if let d = FeetInch.parse(dText) {
                let c = Circle.circumference(diameter: d.inchesValue)
                let arc = Circle.arcLength(radius: d.inchesValue / 2, angleDeg: angle)
                VStack(spacing: SP.s3) {
                    ResultRow(label: "Circumference / pipe wrap",
                              value: FeetInch.approx(inches: c, den: denominator).formatted(toDenominator: denominator),
                              emphasis: true, identifier: "circle.circumference")
                    ResultRow(label: "Decimal inches", value: Fmt.f(c, 4), unit: "in",
                              identifier: "circle.decimal")
                    ResultRow(label: "Arc length",
                              value: FeetInch.approx(inches: arc, den: denominator).formatted(toDenominator: denominator),
                              identifier: "circle.arc")
                    ResultRow(label: "Area", value: Fmt.f(Circle.area(diameter: d.inchesValue) / 144, 4),
                              unit: "sq ft", identifier: "circle.area")
                }
                .spCard()
            }
            DenominatorPicker(denominator: $denominator)
        }
    }
}

#Preview("Roof pitch") { ScrollView { RoofPitchToolView().padding() }.background(SP.background) }
#Preview("Rafter")     { ScrollView { RafterToolView().padding() }.background(SP.background) }
#Preview("Square up")  { ScrollView { DiagonalToolView().padding() }.background(SP.background) }
#Preview("Miter")      { ScrollView { MiterToolView().padding() }.background(SP.background) }
#Preview("Circle")     { ScrollView { CircleToolView().padding() }.background(SP.background) }
