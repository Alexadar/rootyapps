import SwiftUI
import GeometryKit
import ConcreteKit
import DimensionKit

private func f(_ x: Double, _ p: Int = 2) -> String { String(format: "%.\(p)f", x) }

// MARK: Area
struct AreaToolView: View {
    @State private var shape = 0   // 0 rect, 1 triangle, 2 circle
    @State private var a = 10.0
    @State private var b = 12.0
    var body: some View {
        ToolColumns {
            VStack(spacing: 12) {
                CardHeader(title: "Shape")
                SubScreenPicker(titles: AreaShapeChoice.titles, selection: $shape, identifier: "area.shape")
                switch shape {
                case 0:
                    FeetInchField(title: "Length", value: $a, unit: .foot, range: 0...100000)
                    FeetInchField(title: "Width", value: $b, unit: .foot, range: 0...100000)
                case 1:
                    FeetInchField(title: "Base", value: $a, unit: .foot, range: 0...100000)
                    FeetInchField(title: "Height", value: $b, unit: .foot, range: 0...100000)
                default:
                    FeetInchField(title: "Radius", value: $a, unit: .foot, range: 0...100000)
                }
            }.card()
        } outputs: {
            HeroReadout(label: "Area", value: f(area), unit: "ft²", identifier: "area.hero")

            VStack(spacing: 10) {
                CardHeader(title: "Also")
                if shape == 2 { ResultRow(label: "Circumference", value: f(Area.circumference(radius: a)), unit: "ft") }
                ResultRow(label: "In square yards", value: f(area / 9), unit: "yd²")
            }.card()
        }
    }
    private var area: Double { AreaShapeChoice.areaFt2(index: shape, a: a, b: b) }
}

// MARK: Volume
struct VolumeToolView: View {
    @State private var shape = 0   // 0 box, 1 cylinder
    @State private var a = 10.0
    @State private var b = 10.0
    @State private var c = 8.0
    var body: some View {
        ToolColumns {
            VStack(spacing: 12) {
                CardHeader(title: "Solid")
                SubScreenPicker(titles: VolumeShapeChoice.titles, selection: $shape, identifier: "volume.shape")
                if shape == 0 {
                    FeetInchField(title: "Length", value: $a, unit: .foot, range: 0...100000)
                    FeetInchField(title: "Width", value: $b, unit: .foot, range: 0...100000)
                    FeetInchField(title: "Height", value: $c, unit: .foot, range: 0...100000)
                } else {
                    FeetInchField(title: "Diameter", value: $a, unit: .foot, range: 0...100000)
                    FeetInchField(title: "Height", value: $c, unit: .foot, range: 0...100000)
                }
            }.card()
        } outputs: {
            HeroReadout(label: "Volume", value: f(vol), unit: "ft³", identifier: "volume.hero")

            VStack(spacing: 10) {
                CardHeader(title: "Also")
                ResultRow(label: "Cubic yards", value: f(Volume.cubicFeetToYards(vol), 3), unit: "yd³")
            }.card()
        }
    }
    private var vol: Double { VolumeShapeChoice.volumeFt3(index: shape, a: a, b: b, c: c) }
}

// MARK: Concrete
struct ConcreteToolView: View {
    @State private var form = 0    // 0 slab, 1 column
    @State private var lenFt = 10.0
    @State private var widFt = 10.0
    @State private var thick = 4.0     // inches
    @State private var dia = 12.0      // inches
    @State private var depth = 48.0    // inches
    @State private var bagIdx = 0
    @State private var waste = 10.0
    private var bagYield: Double { ConcreteBagChoice.yieldFt3(index: bagIdx) }
    private var ft3w: Double { Concrete.withWaste(cubicFeet: ft3, wastePct: waste) }

    var body: some View {
        ToolColumns {
            VStack(spacing: 12) {
                CardHeader(title: "Pour")
                SubScreenPicker(titles: ConcreteFormChoice.titles, selection: $form, identifier: "concrete.form")
                if form == 0 {
                    FeetInchField(title: "Length", value: $lenFt, unit: .foot, range: 0...10000)
                    FeetInchField(title: "Width", value: $widFt, unit: .foot, range: 0...10000)
                    FeetInchField(title: "Thickness", value: $thick, unit: .inch, range: 0...120)
                } else {
                    NumberField(title: "Diameter", value: $dia, unit: "in", range: 0...600)
                    FeetInchField(title: "Depth", value: $depth, unit: .inch, range: 0...1200)
                }
            }.card()

            VStack(spacing: 12) {
                CardHeader(title: "Bag size")
                SubScreenPicker(titles: ConcreteBagChoice.titles, selection: $bagIdx, identifier: "concrete.bag")
                NumberField(title: "Waste / over-order", value: $waste, unit: "%", range: 0...30)
            }.card()
        } outputs: {
            HeroReadout(label: "Order + \(f(waste,0))% waste",
                        value: f(Concrete.cubicYards(cubicFeet: ft3w), 3), unit: "yd³", identifier: "concrete.hero")
                .reelDemo("concrete", $thick, [4, 5, 6, 8, 6, 5])

            VStack(spacing: 10) {
                CardHeader(title: "Order")
                ResultRow(label: "Net volume", value: f(ft3, 3), unit: "ft³")
                ResultRow(label: "Cubic yards (net)", value: f(Concrete.cubicYards(cubicFeet: ft3), 3), unit: "yd³")
                ResultRow(label: "Bags (+ waste)", value: "\(Concrete.bags(cubicFeet: ft3w, yieldFt3: bagYield))", unit: "bags")
                ResultRow(label: "Ready-mix trucks (10 yd³)", value: "\(ReadyMix.truckLoads(cubicYards: yd3))",
                          tone: ReadyMix.isShortLoad(cubicYards: yd3) ? KC.warn : nil)
                if ReadyMix.isShortLoad(cubicYards: yd3) {
                    Text("Under ~1 yd³ — expect a short-load fee.")
                        .font(.caption2).foregroundStyle(KC.warn).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.card()

            if form == 0 {
                VStack(spacing: 10) {
                    CardHeader(title: "Control joints", trailing: "ACI 360R")
                    let span = max(lenFt, widFt)
                    let rng = ControlJoints.spacingRangeFeet(thicknessIn: thick)
                    ResultRow(label: "Max spacing (2–3× t)", value: "\(f(rng.min,0))–\(f(rng.max,0))", unit: "ft")
                    ResultRow(label: "Joints along \(f(span,0)) ft", value: "\(ControlJoints.joints(lengthFt: span, thicknessIn: thick))")
                }.card()
            }
        }
    }
    private var ft3: Double {
        ConcreteFormChoice.cubicFeet(index: form, lenFt: lenFt, widFt: widFt, thickIn: thick,
                                     diaIn: dia, depthIn: depth)
    }
    private var yd3: Double { Concrete.cubicYards(cubicFeet: ft3) }
}
