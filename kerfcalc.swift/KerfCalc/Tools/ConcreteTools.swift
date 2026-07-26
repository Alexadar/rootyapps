import SwiftUI
import ConcreteKit
import DimensionKit

private func f(_ x: Double, _ p: Int = 2) -> String { String(format: "%.\(p)f", x) }

// MARK: Footing (strip / pad / wall)
struct FootingToolView: View {
    @State private var kind = 0   // 0 strip, 1 pad, 2 wall
    @State private var lenFt = 100.0
    @State private var widIn = 16.0
    @State private var depIn = 8.0
    @State private var padL = 24.0
    @State private var padW = 24.0
    @State private var padD = 12.0
    @State private var wallLen = 40.0
    @State private var wallH = 4.0
    @State private var wallT = 8.0
    @State private var barIdx = 1    // #4
    @State private var runs = 2.0

    private var ft3: Double {
        switch kind {
        case 0: return Footing.continuousCubicFeet(lengthFt: lenFt, widthIn: widIn, depthIn: depIn)
        case 1: return Footing.padCubicFeet(lengthIn: padL, widthIn: padW, depthIn: padD)
        default: return Footing.wallCubicFeet(lengthFt: wallLen, heightFt: wallH, thicknessIn: wallT)
        }
    }
    private var runFeet: Double { kind == 0 ? lenFt : (kind == 2 ? wallLen : 0) }
    private var bar: BarSize { BarSize.allCases[barIdx] }

    var body: some View {
        ToolColumns {
            VStack(spacing: 12) {
                CardHeader(title: "Footing")
                SubScreenPicker(titles: ["Strip", "Pad", "Wall"], selection: $kind)
                switch kind {
                case 0:
                    FeetInchField(title: "Length", value: $lenFt, unit: .foot, range: 0...100000)
                    NumberField(title: "Width", value: $widIn, unit: "in", range: 0...600)
                    FeetInchField(title: "Depth", value: $depIn, unit: .inch, range: 0...600)
                case 1:
                    NumberField(title: "Length", value: $padL, unit: "in", range: 0...600)
                    NumberField(title: "Width", value: $padW, unit: "in", range: 0...600)
                    FeetInchField(title: "Depth", value: $padD, unit: .inch, range: 0...600)
                default:
                    FeetInchField(title: "Length", value: $wallLen, unit: .foot, range: 0...100000)
                    FeetInchField(title: "Height", value: $wallH, unit: .foot, range: 0...100)
                    FeetInchField(title: "Thickness", value: $wallT, unit: .inch, range: 0...48)
                }
            }.card()
        } outputs: {
            HeroReadout(label: "Concrete", value: f(Footing.cubicYards(ft3), 3), unit: "yd³")

            VStack(spacing: 10) {
                CardHeader(title: "Order")
                ResultRow(label: "Volume", value: f(ft3, 2), unit: "ft³")
                ResultRow(label: "80-lb bags", value: "\(Int((ft3 / 0.60).rounded(.up)))", unit: "bags")
            }.card()

            if kind != 1 {
                VStack(spacing: 12) {
                    CardHeader(title: "Continuous rebar")
                    SubScreenPicker(titles: BarSize.allCases.map(\.label), selection: $barIdx)
                    NumberField(title: "Number of runs", value: $runs, range: 0...50)
                    ResultRow(label: "\(bar.label) weight", value: f(bar.weightLbPerFt, 3), unit: "lb/ft")
                    ResultRow(label: "Total steel", value: f(Rebar.weight(bar, lengthFt: runFeet) * runs, 1), unit: "lb")
                }.card()
            }
        }
    }
}

// MARK: Rebar
struct RebarToolView: View {
    @State private var barIdx = 1
    @State private var lenFt = 20.0
    @State private var slabL = 10.0
    @State private var slabW = 10.0
    @State private var spacing = 12.0
    private var bar: BarSize { BarSize.allCases[barIdx] }

    var body: some View {
        ToolColumns {
            VStack(spacing: 12) {
                CardHeader(title: "Bar size", trailing: "ASTM A615")
                SubScreenPicker(titles: BarSize.allCases.map(\.label), selection: $barIdx)
            }.card()
        } outputs: {
            HeroReadout(label: "\(bar.label) unit weight", value: f(bar.weightLbPerFt, 3), unit: "lb/ft")

            VStack(spacing: 10) {
                CardHeader(title: bar.label)
                ResultRow(label: "Diameter", value: f(bar.diameterIn, 3), unit: "in")
                ResultRow(label: "Area", value: f(bar.areaIn2, 2), unit: "in²")
            }.card()

            VStack(spacing: 12) {
                CardHeader(title: "Single run")
                FeetInchField(title: "Length", value: $lenFt, unit: .foot, range: 0...10000)
                ResultRow(label: "Weight", value: f(Rebar.weight(bar, lengthFt: lenFt), 1), unit: "lb")
            }.card()

            VStack(spacing: 12) {
                CardHeader(title: "Slab mat (two-way)")
                FeetInchField(title: "Length", value: $slabL, unit: .foot, range: 0...10000)
                FeetInchField(title: "Width", value: $slabW, unit: .foot, range: 0...10000)
                NumberField(title: "Spacing o.c.", value: $spacing, unit: "in", range: 1...48)
                ResultRow(label: "Bars each way", value: "\(Rebar.barCount(dimensionFt: slabW, spacingIn: spacing)) × \(Rebar.barCount(dimensionFt: slabL, spacingIn: spacing))")
                ResultRow(label: "Lineal feet", value: f(Rebar.matLinealFeet(lengthFt: slabL, widthFt: slabW, spacingIn: spacing), 0), unit: "ft")
                ResultRow(label: "Total weight", value: f(Rebar.matWeight(size: bar, lengthFt: slabL, widthFt: slabW, spacingIn: spacing), 1), unit: "lb")
            }.card()

            VStack(spacing: 10) {
                CardHeader(title: "Laps & hooks", trailing: "rule of thumb")
                ResultRow(label: "Tension lap (40×dₐ)", value: f(Rebar.lapLengthIn(bar), 1), unit: "in")
                ResultRow(label: "90° hook (12×dₐ)", value: f(Rebar.hookExtensionIn(bar), 1), unit: "in")
                Text("Field estimate only — actual lap per ACI 318 §25.5 (f′c, grade, cover).")
                    .font(.caption2).foregroundStyle(KC.textTertiary).frame(maxWidth: .infinity, alignment: .leading)
            }.card()
        }
    }
}

// MARK: Aggregate
struct AggregateToolView: View {
    @State private var lenFt = 20.0
    @State private var widFt = 10.0
    @State private var depIn = 4.0
    @State private var matIdx = 0
    private var mat: AggregateMaterial { AggregateMaterial.allCases[matIdx] }
    private var yd3: Double { Aggregate.cubicYards(lengthFt: lenFt, widthFt: widFt, depthIn: depIn) }

    var body: some View {
        ToolColumns {
            VStack(spacing: 12) {
                CardHeader(title: "Area")
                FeetInchField(title: "Length", value: $lenFt, unit: .foot, range: 0...100000)
                FeetInchField(title: "Width", value: $widFt, unit: .foot, range: 0...100000)
                FeetInchField(title: "Depth", value: $depIn, unit: .inch, range: 0...120)
            }.card()

            VStack(spacing: 12) {
                CardHeader(title: "Material")
                SubScreenPicker(titles: AggregateMaterial.allCases.map { $0.rawValue.components(separatedBy: " ").first ?? $0.rawValue }, selection: $matIdx)
            }.card()
        } outputs: {
            HeroReadout(label: "Tonnage", value: f(Aggregate.tons(cubicYards: yd3, material: mat), 2), unit: "t")

            VStack(spacing: 10) {
                CardHeader(title: "Basis", trailing: "\(f(mat.tonsPerCubicYard, 2)) t/yd³")
                ResultRow(label: "Cubic yards", value: f(yd3, 3), unit: "yd³")
                Text("Density is a typical value — verify tonnage with your supplier.")
                    .font(.caption2).foregroundStyle(KC.textTertiary).frame(maxWidth: .infinity, alignment: .leading)
            }.card()
        }
    }
}

// MARK: Mortar & grout
struct MortarToolView: View {
    @State private var mode = 0   // 0 block, 1 brick, 2 grout
    @State private var count = 100.0
    @State private var wallArea = 100.0

    private var hero: (String, String, String) { MortarHero.hero(mode: mode, count: count, wallArea: wallArea) }
    var body: some View {
        ToolColumns {
            VStack(spacing: 12) {
                CardHeader(title: mode == 2 ? "CMU wall" : "Units laid",
                           trailing: mode == 2 ? "NCMA TEK 3-2A" : "Quikrete #1136")
                SubScreenPicker(titles: ["Block", "Brick", "Grout"], selection: $mode)
                if mode == 2 {
                    NumberField(title: "Wall area (fully grouted 8\")", value: $wallArea, unit: "ft²", range: 0...1000000)
                } else {
                    NumberField(title: mode == 0 ? "Block count" : "Brick count", value: $count, range: 0...1000000)
                }
            }.card()
        } outputs: {
            HeroReadout(label: hero.0, value: hero.1, unit: hero.2)

            VStack(spacing: 10) {
                CardHeader(title: "Coverage")
                if mode == 2 {
                    ResultRow(label: "Grout volume", value: f(Grout.cubicFeet(wallAreaFt2: wallArea), 1), unit: "ft³")
                    ResultRow(label: "Rate", value: "2.1 yd³ / 100 ft²")
                } else {
                    ResultRow(label: "80-lb Mason Mix", value: mode == 0 ? "13 blk/bag" : "37 brk/bag")
                }
            }.card()
        }
    }
}

// MARK: Pavers & retaining-wall block
struct PaversToolView: View {
    @State private var mode = 0     // 0 pavers, 1 retaining wall
    @State private var area = 200.0
    @State private var pL = 8.0
    @State private var pW = 4.0
    @State private var waste = 10.0
    @State private var wallLenFt = 20.0
    @State private var wallHInFt = 24.0
    @State private var blkL = 12.0
    @State private var blkH = 6.0

    private var hero: (String, String, String) {
        PaversHero.hero(mode: mode, area: area, pL: pL, pW: pW, waste: waste,
                        wallLenFt: wallLenFt, wallHIn: wallHInFt, blkL: blkL, blkH: blkH)
    }
    var body: some View {
        ToolColumns {
            VStack(spacing: 12) {
                CardHeader(title: "Hardscape")
                SubScreenPicker(titles: ["Pavers", "Retaining wall"], selection: $mode)
                if mode == 0 {
                    NumberField(title: "Area", value: $area, unit: "ft²", range: 0...1000000)
                    NumberField(title: "Paver length", value: $pL, unit: "in", range: 1...48)
                    NumberField(title: "Paver width", value: $pW, unit: "in", range: 1...48)
                    NumberField(title: "Waste", value: $waste, unit: "%", range: 0...50)
                } else {
                    FeetInchField(title: "Wall length", value: $wallLenFt, unit: .foot, range: 0...10000)
                    NumberField(title: "Wall height", value: $wallHInFt, unit: "in", range: 0...600)
                    NumberField(title: "Block length", value: $blkL, unit: "in", range: 1...48)
                    NumberField(title: "Block height", value: $blkH, unit: "in", range: 1...24)
                }
            }.card()
        } outputs: {
            HeroReadout(label: hero.0, value: hero.1, unit: hero.2)

            VStack(spacing: 10) {
                CardHeader(title: "Basis")
                if mode == 0 {
                    ResultRow(label: "Per ft²", value: f(Hardscape.paversPerFt2(lengthIn: pL, widthIn: pW), 2))
                } else {
                    ResultRow(label: "Courses", value: "\(Hardscape.courses(wallHeightIn: wallHInFt, blockHeightIn: blkH))")
                }
                Text("Pattern waste is editable (running bond ≈5 %, herringbone ≈10–15 %).")
                    .font(.caption2).foregroundStyle(KC.textTertiary).frame(maxWidth: .infinity, alignment: .leading)
            }.card()
        }
    }
}
