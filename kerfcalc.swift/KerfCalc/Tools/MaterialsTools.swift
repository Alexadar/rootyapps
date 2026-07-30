import SwiftUI
import MaterialsKit
import DimensionKit

private func f(_ x: Double, _ p: Int = 2) -> String { String(format: "%.\(p)f", x) }

// MARK: Roofing
struct RoofingToolView: View {
    @State private var plan = 2000.0   // ft² footprint
    @State private var rise = 6.0      // X/12
    @State private var waste = 10.0
    private var area: Double { Roofing.roofArea(planAreaFt2: plan, riseIn12: rise) }
    var body: some View {
        ToolColumns {
            VStack(spacing: 12) {
                CardHeader(title: "Roof")
                NumberField(title: "Plan (footprint) area", value: $plan, unit: "ft²", range: 0...1000000)
                NumberField(title: "Pitch (rise per 12)", value: $rise, unit: "/12", range: 0...36)
                NumberField(title: "Waste", value: $waste, unit: "%", range: 0...50)
            }.card()
        } outputs: {
            HeroReadout(label: "Roofing squares", value: f(Roofing.squares(roofAreaFt2: area)), unit: "sq", identifier: "roofing.hero")
                .reelDemo("roofing", $rise, [6, 8, 10, 12, 9, 6])

            VStack(spacing: 10) {
                CardHeader(title: "Coverage")
                ResultRow(label: "Pitch multiplier", value: f(Roofing.pitchMultiplier(riseIn12: rise), 4))
                ResultRow(label: "Roof surface area", value: f(area), unit: "ft²")
                ResultRow(label: "Squares + waste", value: f(Roofing.squaresWithWaste(roofAreaFt2: area, wastePct: waste)), unit: "sq")
            }.card()
        }
    }
}

// MARK: Estimate (drywall / paint / block)
struct EstimateToolView: View {
    @State private var mode = 0
    @State private var area = 1000.0
    @State private var coats = 2.0

    private var hero: (String, String, String) { EstimateHero.hero(mode: mode, area: area, coats: Int(coats)) }
    var body: some View {
        ToolColumns {
            VStack(spacing: 12) {
                CardHeader(title: "Estimate")
                SubScreenPicker(titles: ["Drywall", "Paint", "Block"], selection: $mode, identifier: "estimate.mode")
                NumberField(title: "Wall area", value: $area, unit: "ft²", range: 0...1000000)
                if mode == 1 { NumberField(title: "Coats", value: $coats, range: 1...5) }
            }.card()
        } outputs: {
            HeroReadout(label: hero.0, value: hero.1, unit: hero.2, identifier: "estimate.hero")

            VStack(spacing: 10) {
                CardHeader(title: "Basis")
                switch mode {
                case 0: ResultRow(label: "4×8 sheet + 10% waste", value: "32", unit: "ft²/sheet")
                case 1: ResultRow(label: "Coverage", value: "350", unit: "ft²/gal")
                default:
                    ResultRow(label: "CMU 8×16", value: "1.125", unit: "/ft²")
                    ResultRow(label: "Modular brick (+5%)", value: "\(Estimate.units(areaFt2: area, perFt2: Estimate.modularBrickPerFt2))", unit: "brick")
                }
            }.card()
        }
    }
}

// MARK: Miter (compound crown)
struct MiterToolView: View {
    @State private var spring = 38.0
    @State private var sides = 4.0
    private var result: (miter: Double, bevel: Double) { CompoundMiter.compound(springDeg: spring, sides: Int(sides)) }
    var body: some View {
        ToolColumns {
            VStack(spacing: 12) {
                CardHeader(title: "Crown")
                NumberField(title: "Spring angle", value: $spring, unit: "°", range: 0...90)
                NumberField(title: "Sides (corner)", value: $sides, range: 3...24)
            }.card()
        } outputs: {
            HeroReadout(label: "Miter angle", value: f(result.miter), unit: "°", identifier: "miter.hero")

            VStack(spacing: 10) {
                CardHeader(title: "Saw settings")
                ResultRow(label: "Bevel", value: f(result.bevel), unit: "°")
                ResultRow(label: "Flat miter (each joint)", value: f(CompoundMiter.simpleMiterDeg(sides: Int(sides))), unit: "°")
            }.card()
        }
    }
}

// MARK: Lumber (board feet)
struct LumberToolView: View {
    @State private var t = 2.0
    @State private var w = 6.0
    @State private var lenFt = 10.0
    @State private var pieces = 1.0
    private var bf: Double { Estimate.boardFeet(thicknessIn: t, widthIn: w, lengthFt: lenFt) }
    var body: some View {
        ToolColumns {
            VStack(spacing: 12) {
                CardHeader(title: "Board")
                FeetInchField(title: "Thickness", value: $t, unit: .inch, range: 0...48)
                NumberField(title: "Width", value: $w, unit: "in", range: 0...96)
                FeetInchField(title: "Length", value: $lenFt, unit: .foot, range: 0...100)
                NumberField(title: "Pieces", value: $pieces, range: 1...10000)
            }.card()
        } outputs: {
            HeroReadout(label: "Total board feet", value: f(bf * pieces, 2), unit: "bf", identifier: "lumber.hero")

            VStack(spacing: 10) {
                CardHeader(title: "Per piece")
                ResultRow(label: "Board feet", value: f(bf, 3), unit: "bf")
            }.card()
        }
    }
}
