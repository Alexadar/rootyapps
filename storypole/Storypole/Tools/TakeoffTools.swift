import SwiftUI
import DimensionKit
import VolumeKit

// MARK: - Area

struct AreaToolView: View {
    @State private var aText = "12' 4\""
    @State private var bText = "12' 4\""
    @State private var shape: Shape = .rectangle

    enum Shape: String, CaseIterable { case rectangle = "Rectangle", triangle = "Triangle", circle = "Circle" }

    private var a: FeetInch? { FeetInch.parse(aText) }
    private var b: FeetInch? { FeetInch.parse(bText) }

    var body: some View {
        VStack(alignment: .leading, spacing: SP.s3) {
            Picker("Shape", selection: $shape) {
                ForEach(Shape.allCases, id: \.self) { Text(L.loc($0.rawValue)).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("area.shape")

            DimensionField(label: shape == .circle ? "Diameter" : "Length", text: $aText,
                           identifier: "area.a")
            if shape != .circle {
                DimensionField(label: shape == .triangle ? "Height" : "Width", text: $bText,
                               identifier: "area.b")
            }

            if let ft2 = squareFeet {
                VStack(spacing: SP.s3) {
                    ResultRow(label: "Area", value: Fmt.f(ft2, 2), unit: "sq ft", emphasis: true,
                              identifier: "area.result")
                    ResultRow(label: "Square inches", value: Fmt.f(ft2 * 144, 0), unit: "in²",
                              identifier: "area.in2")
                    ResultRow(label: "Square yards", value: Fmt.f(ft2 / 9, 3), unit: "yd²",
                              identifier: "area.yd2")
                }
                .spCard()
            }
        }
    }

    private var squareFeet: Double? {
        guard let a else { return nil }
        switch shape {
        case .rectangle:
            guard let b else { return nil }
            return Area.squareFeet(lengthIn: a.inchesValue, widthIn: b.inchesValue)
        case .triangle:
            guard let b else { return nil }
            return Area.triangle(base: a.inchesValue, height: b.inchesValue) / 144
        case .circle:
            return Area.rectangle(length: 1, width: 1) * .pi * pow(a.inchesValue / 2, 2) / 144
        }
    }
}

// MARK: - Volume

struct VolumeToolView: View {
    @State private var lText = "10'"
    @State private var wText = "8'"
    @State private var hText = "4\""
    @State private var solid: Solid = .box

    enum Solid: String, CaseIterable { case box = "Box", cylinder = "Cylinder", sphere = "Sphere" }

    var body: some View {
        VStack(alignment: .leading, spacing: SP.s3) {
            Picker("Solid", selection: $solid) {
                ForEach(Solid.allCases, id: \.self) { Text(L.loc($0.rawValue)).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("volume.solid")

            DimensionField(label: solid == .box ? "Length" : "Diameter", text: $lText,
                           identifier: "volume.l")
            if solid == .box {
                DimensionField(label: "Width", text: $wText, identifier: "volume.w")
            }
            if solid != .sphere {
                DimensionField(label: solid == .box ? "Height" : "Depth", text: $hText,
                               identifier: "volume.h")
            }

            if let ft3 = cubicFeet {
                VStack(spacing: SP.s3) {
                    ResultRow(label: "Volume", value: Fmt.f(ft3, 3), unit: "cu ft", emphasis: true,
                              identifier: "volume.result")
                    ResultRow(label: "Cubic yards", value: Fmt.f(Volume.cubicFeetToYards(ft3), 3),
                              unit: "yd³", identifier: "volume.yd3")
                    ResultRow(label: "Cubic metres", value: Fmt.f(Volume.cubicYardsToMetres(Volume.cubicFeetToYards(ft3)), 4),
                              unit: "m³", identifier: "volume.m3")
                }
                .spCard()
            }
        }
    }

    private var cubicFeet: Double? {
        let l = FeetInch.parse(lText)?.inchesValue
        let w = FeetInch.parse(wText)?.inchesValue
        let h = FeetInch.parse(hText)?.inchesValue
        switch solid {
        case .box:
            guard let l, let w, let h else { return nil }
            return Volume.box(length: l, width: w, height: h) / Volume.cubicInchesPerCubicFoot
        case .cylinder:
            guard let l, let h else { return nil }
            return Volume.cylinder(diameter: l, height: h) / Volume.cubicInchesPerCubicFoot
        case .sphere:
            guard let l else { return nil }
            return Volume.sphere(radius: l / 2) / Volume.cubicInchesPerCubicFoot
        }
    }
}

// MARK: - Cubic yards (concrete)

struct CubicYardsToolView: View {
    @State private var lengthFt = 10.0
    @State private var widthFt = 10.0
    @State private var thicknessIn = 4.0
    @State private var wastePct = 10.0

    var body: some View {
        VStack(alignment: .leading, spacing: SP.s3) {
            NumberField(label: "Length", value: $lengthFt, unit: "ft", range: 0...5000,
                        identifier: "yards.length")
            NumberField(label: "Width", value: $widthFt, unit: "ft", range: 0...5000,
                        identifier: "yards.width")
            NumberField(label: "Thickness", value: $thicknessIn, unit: "in", range: 0...240,
                        identifier: "yards.thickness")
            NumberField(label: "Waste allowance", value: $wastePct, unit: "%", range: 0...50,
                        identifier: "yards.waste")

            let ft3 = Concrete.slabCubicFeet(lengthFt: lengthFt, widthFt: widthFt, thicknessInches: thicknessIn)
            let withWaste = Concrete.withWaste(cubicFeet: ft3, wastePct: wastePct)

            VStack(spacing: SP.s3) {
                ResultRow(label: "Cubic yards (with waste)",
                          value: Fmt.f(Concrete.cubicYards(cubicFeet: withWaste), 2), unit: "yd³",
                          emphasis: true, identifier: "yards.result")
                ResultRow(label: "Cubic feet", value: Fmt.f(ft3, 2), unit: "cu ft",
                          identifier: "yards.ft3")
                ResultRow(label: "80 lb bags", value: String(Concrete.bags(cubicFeet: withWaste)),
                          identifier: "yards.bags")
            }
            .spCard()

            Text("""
                 Cubic yard → cubic metre is 7.645549E−01 (NIST SP 811 §B.8), which is 0.9144³. \
                 Bag yields are QUIKRETE's published datasheet figures; the waste allowance is an \
                 estimating convention, not a standard.
                 """)
                .font(SPType.footnote).foregroundStyle(SP.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview("Area")        { ScrollView { AreaToolView().padding() }.background(SP.background) }
#Preview("Volume")      { ScrollView { VolumeToolView().padding() }.background(SP.background) }
#Preview("Cubic yards") { ScrollView { CubicYardsToolView().padding() }.background(SP.background) }
