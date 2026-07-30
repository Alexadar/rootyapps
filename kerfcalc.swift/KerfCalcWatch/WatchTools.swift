import SwiftUI
import FramingKit
import PipeKit
import GeometryKit
import ConcreteKit
import MaterialsKit
import DimensionKit

// All 20 wrist tool screens — the phone's whole catalog, in kerfcalc's own design language:
// a concrete paper body, matte white input cards, and ONE dark graphite instrument holding the hero.
// See `WatchComponents.swift` for why this is not the dark house pattern.
//
// ## The order, and why it is this and not overtonelab's
//
// `hero → crown fields → picker → secondary rows → pinned rows`
//
// overtonelab puts its fields *last*, after the secondaries. That works there because its screens carry
// one secondary row. Ours carry two or three plus a pinned row, and putting the fields last pushed them
// **below the fold on a 40 mm screen** — measured: `KerfCalcWatchUITests` could not find
// `input.pavers.area` or `input.mortar.count` at all, because watchOS does not publish accessibility
// leaves that have never been on screen, and four more screens' fields never moved. A control you have
// to scroll to find is a worse failure than a number you have to scroll to read, so the answer and the
// things you turn sit together at the top and the detail goes underneath.
//
// ## What earns a wrist control
//
// **≤ 2 crown fields + ≤ 1 picker.** A picker only when the mode *is* the tool. Any phone input not
// exposed is pinned at **the phone's own default** and shown as a `WatchPinnedRow` — this is a tool
// people cut material against, so a fixed value has to be visible, not implied.
//
// ## The rule that keeps the crown alive
//
// Every Button and Picker calls `crownFocus.reclaim()`. `WatchIndexPicker` bakes the call in so a new
// screen cannot forget it; `CrownFocusChecks` is the regression.

// MARK: - Shared bits

/// An index-selecting picker that always hands the crown back.
///
/// The `onChange → reclaim()` is inside the component on purpose: a Picker takes focus exactly like a
/// Button, and a call site that forgets kills the crown with no visible symptom.
private struct WatchIndexPicker: View {
    let titles: [String]
    @Binding var index: Int
    let accent: Color
    let identifier: String
    @EnvironmentObject private var crownFocus: CrownFocus

    var body: some View {
        Picker("", selection: $index) {
            ForEach(titles.indices, id: \.self) { i in Text(titles[i]).tag(i) }
        }
        .watchPicker(tint: accent, identifier: identifier)
        .onChange(of: index) { _, _ in crownFocus.reclaim() }
    }
}

/// The three fitting angles a fitter actually buys. `PipeFittingChoice` also offers "Other" with a
/// custom angle; that needs a second numeric input, so it stays on the phone.
private let watchFittingTitles = Array(PipeFittingChoice.titles.prefix(3))

// MARK: - Framing · Rafter

struct RafterWatch: View {
    @EnvironmentObject private var crownFocus: CrownFocus
    @State private var rise = 6.0        // X-in-12
    @State private var runFt = 12.0
    @State private var active = 0
    private let accent = Tool.rafter.accent
    private let ridge = 1.5              // phone default — a 2x ridge board
    private let overhang = 12.0          // phone default

    var body: some View {
        WatchToolScreen(tool: .rafter) {
            WatchHero(label: "Cut length",
                      value: WFmt.f(Rafter.actualLength(rise: rise, runFeet: runFt,
                                                        ridgeThicknessIn: ridge, overhangIn: overhang), 2),
                      unit: "in", identifier: "result.rafter.hero")
            CrownField(label: "PITCH", value: $rise, unit: "/12", step: 1, range: 1...24,
                       targeted: active == 0, accent: accent, places: 0,
                       identifier: "input.rafter.pitch")
                .onTapGesture { active = 0; crownFocus.reclaim() }
            CrownField(label: "RUN", value: $runFt, unit: "ft", step: 0.5, range: 1...80,
                       targeted: active == 1, accent: accent, places: 1,
                       identifier: "input.rafter.run")
                .onTapGesture { active = 1; crownFocus.reclaim() }

            WatchRow(label: "Line length", value: WFmt.f(Rafter.commonLength(rise: rise, runFeet: runFt), 2),
                     unit: "in", identifier: "result.rafter.lineLength")
            WatchRow(label: "Plumb cut", value: WFmt.f(Rafter.plumbCutDegrees(rise: rise), 2),
                     unit: "°", identifier: "result.rafter.plumbCut")
            WatchPinnedRow(label: "Ridge · overhang", value: "1.5\" · 12\"", identifier: "fixed.rafter")
        }
    }
}

// MARK: - Framing · Stairs

/// `StairCode` is a struct and only `Equatable`, so it cannot be a `Picker` tag. This wraps the two
/// shipped codes in a Hashable enum rather than selecting by array index — an index that drifts out
/// of step with its list hands a *correct* Kit the *wrong* input, and no test can see it.
private enum WatchStairCode: String, CaseIterable, Identifiable {
    case irc, ibc
    var id: String { rawValue }
    var label: String { self == .irc ? "IRC" : "IBC" }
    var code: StairCode { self == .irc ? .irc2021 : .ibc }
}

struct StairsWatch: View {
    @EnvironmentObject private var crownFocus: CrownFocus
    @State private var totalRise = 108.0     // 9'-0"
    @State private var codeSel: WatchStairCode = .irc
    private let accent = Tool.stairs.accent

    var body: some View {
        WatchToolScreen(tool: .stairs) {
            // The wrist has no tread-depth input, so the tread follows the selected code's minimum
            // (IRC 10", IBC 11"). Left at the Kit's 10" default, picking IBC silently produced a
            // layout that violates the very code just selected. `Stairs.solve` never alters input to
            // fit a code — choosing the depth is the caller's job, so it is made here, visibly.
            let code = codeSel.code
            let r = Stairs.solve(totalRise: totalRise, treadDepth: code.minTread, code: code)

            WatchHero(label: "Risers", value: "\(r.risers)",
                      unit: "@ \(WFmt.f(r.riserHeight, 2))\"", identifier: "result.stairs.hero")
            CrownField(label: "TOTAL RISE", value: $totalRise, unit: "in", step: 0.25, range: 12...300,
                       targeted: true, accent: accent, places: 2,
                       identifier: "input.stairs.totalRise")
                .onTapGesture { crownFocus.reclaim() }

            Picker("", selection: $codeSel) {
                ForEach(WatchStairCode.allCases) { Text($0.label).tag($0) }
            }
            .watchPicker(tint: accent, identifier: "input.stairs.code")
            .onChange(of: codeSel) { _, _ in crownFocus.reclaim() }   // a Picker takes focus too

            WatchRow(label: "Riser height", value: WFmt.f(r.riserHeight, 2) + (r.riserOK ? "" : " ⚠"),
                     unit: "in", emphasis: !r.riserOK, accent: KC.warn,
                     identifier: "result.stairs.riserHeight")
            WatchRow(label: "Treads",
                     value: "\(r.treads) @ " + WFmt.f(r.treadDepth, 0) + "\"" + (r.treadOK ? "" : " ⚠"),
                     identifier: "result.stairs.treads")
            WatchRow(label: "Stringer", value: WFmt.f(r.stringerLength, 1), unit: "in",
                     identifier: "result.stairs.stringer")
        }
    }
}

// MARK: - Framing · Right Angle

struct PitchWatch: View {
    @EnvironmentObject private var crownFocus: CrownFocus
    @State private var rise = 6.0
    @State private var run  = 12.0
    @State private var active = 0
    private let accent = Tool.pitch.accent

    var body: some View {
        WatchToolScreen(tool: .pitch) {
            WatchHero(label: "Angle", value: WFmt.f(Pitch.angleDegrees(rise: rise, run: run), 1),
                      unit: "°", identifier: "result.pitch.hero")
            CrownField(label: "RISE", value: $rise, unit: "in", step: 0.25, range: 0...240,
                       targeted: active == 0, accent: accent, places: 2,
                       identifier: "input.pitch.rise")
                .onTapGesture { active = 0; crownFocus.reclaim() }
            CrownField(label: "RUN", value: $run, unit: "in", step: 0.25, range: 0.25...240,
                       targeted: active == 1, accent: accent, places: 2,
                       identifier: "input.pitch.run")
                .onTapGesture { active = 1; crownFocus.reclaim() }

            WatchRow(label: "Diagonal", value: WFmt.f(Pitch.diagonal(rise: rise, run: run), 2),
                     unit: "in", emphasis: true, accent: accent, identifier: "result.pitch.diagonal")
            WatchRow(label: "Pitch", value: WFmt.f(Pitch.riseInTwelve(rise: rise, run: run), 1) + "/12",
                     identifier: "result.pitch.ratio")
            WatchRow(label: "Slope", value: WFmt.f(Pitch.slopePercent(rise: rise, run: run), 1),
                     unit: "%", identifier: "result.pitch.slope")
        }
    }
}

// MARK: - Concrete · Concrete

struct ConcreteWatch: View {
    @EnvironmentObject private var crownFocus: CrownFocus
    @State private var lengthFt = 10.0
    @State private var widthFt  = 10.0
    @State private var thickIn  = 4.0
    @State private var active = 0
    private let accent = Tool.concrete.accent

    var body: some View {
        WatchToolScreen(tool: .concrete) {
            let cf = Concrete.slabCubicFeet(lengthFt: lengthFt, widthFt: widthFt, thicknessInches: thickIn)

            WatchHero(label: "Volume", value: WFmt.f(Concrete.cubicYards(cubicFeet: cf), 2),
                      unit: "yd³", identifier: "result.concrete.hero")
            CrownField(label: "LENGTH", value: $lengthFt, unit: "ft", step: 0.5, range: 0...1000,
                       targeted: active == 0, accent: accent, places: 1,
                       identifier: "input.concrete.length")
                .onTapGesture { active = 0; crownFocus.reclaim() }
            CrownField(label: "WIDTH", value: $widthFt, unit: "ft", step: 0.5, range: 0...1000,
                       targeted: active == 1, accent: accent, places: 1,
                       identifier: "input.concrete.width")
                .onTapGesture { active = 1; crownFocus.reclaim() }

            // Thickness stepper — the sibling buttons that would kill the crown without reclaim().
            // `−` light, `+` graphite: the same two-weight language as the phone's StepperRow (§5).
            HStack(spacing: 6) {
                Text("THICK").font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(KCW.inkSoft).lineLimit(1).layoutPriority(1)
                Spacer(minLength: 0)
                Button { thickIn = max(0.5, thickIn - 0.5); crownFocus.reclaim() } label: {
                    Image(systemName: "minus")
                }
                .accessibilityIdentifier("input.concrete.thick.dec")
                .accessibilityLabel("Decrease thickness")
                Text(WFmt.f(thickIn, 1) + "\"")
                    .font(.system(.headline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(KCW.ink).monospacedDigit()
                    .lineLimit(1).fixedSize()      // else the inch mark wraps between the steppers
                    .accessibilityIdentifier("input.concrete.thick.value")
                Button { thickIn = min(48, thickIn + 0.5); crownFocus.reclaim() } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("input.concrete.thick.inc")
                .accessibilityLabel("Increase thickness")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .frame(minHeight: KCW.hit)
            .background(KCW.card, in: .rect(cornerRadius: KCW.rCard))
            .overlay(RoundedRectangle(cornerRadius: KCW.rCard).strokeBorder(KCW.hairline, lineWidth: 1))

            WatchRow(label: "80 lb bags", value: "\(Concrete.bags(cubicFeet: cf))",
                     identifier: "result.concrete.bags")
            WatchRow(label: "Cubic feet", value: WFmt.f(cf, 1), unit: "ft³",
                     identifier: "result.concrete.cubicFeet")
            WatchPinnedRow(label: "Net · no waste", value: "phone adds %", identifier: "fixed.concrete")
        }
    }
}

// MARK: - Concrete · Footing

struct FootingWatch: View {
    @EnvironmentObject private var crownFocus: CrownFocus
    @State private var lenFt = 100.0
    @State private var widIn = 16.0
    @State private var active = 0
    private let accent = Tool.footing.accent
    private let depIn = 8.0              // phone default

    var body: some View {
        WatchToolScreen(tool: .footing) {
            // Strip footing only — pad and wall need three more dimensions each, so they stay on the
            // phone. `FootingKindChoice.cubicFeet(index: 0, …)` is the same call the phone makes.
            let ft3 = FootingKindChoice.cubicFeet(index: 0, lenFt: lenFt, widIn: widIn, depIn: depIn,
                                                 padL: 0, padW: 0, padD: 0,
                                                 wallLen: 0, wallH: 0, wallT: 0)

            WatchHero(label: "Concrete", value: WFmt.f(Footing.cubicYards(ft3), 3),
                      unit: "yd³", identifier: "result.footing.hero")
            CrownField(label: "LENGTH", value: $lenFt, unit: "ft", step: 1, range: 1...2000,
                       targeted: active == 0, accent: accent, places: 0,
                       identifier: "input.footing.length")
                .onTapGesture { active = 0; crownFocus.reclaim() }
            CrownField(label: "WIDTH", value: $widIn, unit: "in", step: 1, range: 4...48,
                       targeted: active == 1, accent: accent, places: 0,
                       identifier: "input.footing.width")
                .onTapGesture { active = 1; crownFocus.reclaim() }

            WatchRow(label: "Volume", value: WFmt.f(ft3, 2), unit: "ft³",
                     identifier: "result.footing.cubicFeet")
            WatchRow(label: "80 lb bags", value: "\(Int((ft3 / Concrete.bag80lbYieldFt3).rounded(.up)))",
                     identifier: "result.footing.bags")
            WatchPinnedRow(label: "Strip · depth", value: "8\"", identifier: "fixed.footing")
        }
    }
}

// MARK: - Concrete · Rebar

struct RebarWatch: View {
    @EnvironmentObject private var crownFocus: CrownFocus
    // Bind the enum itself, never an index into `allCases` — `.n4` cannot drift, `[1]` can.
    @State private var size: BarSize = .n4
    @State private var lengthFt = 20.0
    private let accent = Tool.rebar.accent

    var body: some View {
        WatchToolScreen(tool: .rebar) {
            WatchHero(label: "Weight", value: WFmt.f(Rebar.weight(size, lengthFt: lengthFt), 1),
                      unit: "lb", identifier: "result.rebar.hero")
            CrownField(label: "LENGTH", value: $lengthFt, unit: "ft", step: 1, range: 0...400,
                       targeted: true, accent: accent, places: 0,
                       identifier: "input.rebar.length")
                .onTapGesture { crownFocus.reclaim() }

            Picker("", selection: $size) {
                ForEach(BarSize.allCases) { Text($0.label).tag($0) }
            }
            .watchPicker(tint: accent, identifier: "input.rebar.bar")
            .onChange(of: size) { _, _ in crownFocus.reclaim() }

            WatchRow(label: "Per foot", value: WFmt.f(size.weightLbPerFt, 3), unit: "lb/ft",
                     identifier: "result.rebar.perFoot")
            WatchRow(label: "Diameter", value: WFmt.f(size.diameterIn, 3), unit: "in",
                     identifier: "result.rebar.diameter")
            WatchRow(label: "Lap (40×d)", value: WFmt.f(Rebar.lapLengthIn(size), 1), unit: "in",
                     identifier: "result.rebar.lap")
        }
    }
}

// MARK: - Concrete · Aggregate

struct AggregateWatch: View {
    @EnvironmentObject private var crownFocus: CrownFocus
    @State private var lenFt = 20.0
    @State private var widFt = 10.0
    @State private var matIdx = 0
    @State private var active = 0
    private let accent = Tool.aggregate.accent
    private let depIn = 4.0              // phone default — a standard base course

    var body: some View {
        WatchToolScreen(tool: .aggregate) {
            let yd3 = Aggregate.cubicYards(lengthFt: lenFt, widthFt: widFt, depthIn: depIn)
            let mat = AggregateMaterialChoice.material(index: matIdx)

            WatchHero(label: "Tonnage", value: WFmt.f(Aggregate.tons(cubicYards: yd3, material: mat), 2),
                      unit: "t", identifier: "result.aggregate.hero")
            CrownField(label: "LENGTH", value: $lenFt, unit: "ft", step: 1, range: 1...1000,
                       targeted: active == 0, accent: accent, places: 0,
                       identifier: "input.aggregate.length")
                .onTapGesture { active = 0; crownFocus.reclaim() }
            CrownField(label: "WIDTH", value: $widFt, unit: "ft", step: 1, range: 1...500,
                       targeted: active == 1, accent: accent, places: 0,
                       identifier: "input.aggregate.width")
                .onTapGesture { active = 1; crownFocus.reclaim() }

            WatchIndexPicker(titles: AggregateMaterialChoice.titles, index: $matIdx,
                             accent: accent, identifier: "input.aggregate.material")

            WatchRow(label: "Cubic yards", value: WFmt.f(yd3, 3), unit: "yd³",
                     identifier: "result.aggregate.cubicYards")
            WatchRow(label: "Per yd³", value: WFmt.f(mat.tonsPerCubicYard, 2), unit: "t",
                     identifier: "result.aggregate.rate")
            WatchPinnedRow(label: "Depth", value: "4\"", identifier: "fixed.aggregate")
        }
    }
}

// MARK: - Concrete · Pavers

struct PaversWatch: View {
    @EnvironmentObject private var crownFocus: CrownFocus
    @State private var mode = 0            // 0 pavers, 1 retaining wall
    @State private var area = 200.0
    @State private var wallLenFt = 20.0
    private let accent = Tool.pavers.accent
    // Phone defaults: an 8×4" paver, 10% waste, a 12×6" wall block, 24" of wall height.
    private let pL = 8.0, pW = 4.0, waste = 10.0, wallHIn = 24.0, blkL = 12.0, blkH = 6.0

    var body: some View {
        WatchToolScreen(tool: .pavers) {
            let hero = PaversHero.hero(mode: mode, area: area, pL: pL, pW: pW, waste: waste,
                                       wallLenFt: wallLenFt, wallHIn: wallHIn, blkL: blkL, blkH: blkH)

            WatchHero(label: hero.label, value: hero.value, unit: hero.unit,
                      identifier: "result.pavers.hero")
            // The mode picker swaps WHICH field is mounted — pavers are priced by area, a wall by its
            // length — so the field changes rather than being relabelled over a wrong binding.
            if mode == 0 {
                CrownField(label: "AREA", value: $area, unit: "ft²", step: 5, range: 1...20000,
                           targeted: true, accent: accent, places: 0,
                           identifier: "input.pavers.area")
                    .onTapGesture { crownFocus.reclaim() }
            } else {
                CrownField(label: "WALL LENGTH", value: $wallLenFt, unit: "ft", step: 1, range: 1...500,
                           targeted: true, accent: accent, places: 0,
                           identifier: "input.pavers.wallLength")
                    .onTapGesture { crownFocus.reclaim() }
            }

            WatchIndexPicker(titles: ["Pavers", "Wall"], index: $mode,
                             accent: accent, identifier: "input.pavers.mode")

            // The pinned values are folded into the row's LABEL rather than given their own line.
            //
            // With a separate pinned row this screen came to ~198 pt against a 40 mm viewport's 197 —
            // *just* scrollable. A `ScrollView` that can scroll by one point makes the crown ambiguous:
            // it sometimes drove the field and sometimes scrolled, and when it scrolled the field left
            // the screen entirely. One line shorter and the screen fits, so the crown is unambiguous.
            // Nothing is hidden; the fixed values still read on screen.
            if mode == 0 {
                WatchRow(label: "Per ft² · 8×4\" +10%",
                         value: WFmt.f(Hardscape.paversPerFt2(lengthIn: pL, widthIn: pW), 2),
                         identifier: "result.pavers.perFt2")
            } else {
                WatchRow(label: "Courses · 12×6\" of 24\"",
                         value: "\(Hardscape.courses(wallHeightIn: wallHIn, blockHeightIn: blkH))",
                         identifier: "result.pavers.courses")
            }
        }
    }
}

// MARK: - Takeoff · Area

struct AreaWatch: View {
    @EnvironmentObject private var crownFocus: CrownFocus
    @State private var shape = 0
    @State private var a = 10.0
    @State private var b = 12.0
    @State private var active = 0
    private let accent = Tool.area.accent

    var body: some View {
        WatchToolScreen(tool: .area) {
            let ft2 = AreaShapeChoice.areaFt2(index: shape, a: a, b: b)

            WatchHero(label: "Area", value: WFmt.f(ft2, 2), unit: "ft²", identifier: "result.area.hero")
            // A circle takes only a radius, so the second field is hidden rather than ignored — a
            // control that does nothing is worse than no control.
            CrownField(label: shape == 2 ? "RADIUS" : (shape == 1 ? "BASE" : "LENGTH"),
                       value: $a, unit: "ft", step: 0.5, range: 0...5000,
                       targeted: active == 0, accent: accent, places: 1,
                       identifier: "input.area.a")
                .onTapGesture { active = 0; crownFocus.reclaim() }
            if shape != 2 {
                CrownField(label: shape == 1 ? "HEIGHT" : "WIDTH",
                           value: $b, unit: "ft", step: 0.5, range: 0...5000,
                           targeted: active == 1, accent: accent, places: 1,
                           identifier: "input.area.b")
                    .onTapGesture { active = 1; crownFocus.reclaim() }
            }

            WatchIndexPicker(titles: AreaShapeChoice.titles, index: $shape,
                             accent: accent, identifier: "input.area.shape")

            WatchRow(label: "Square yards", value: WFmt.f(ft2 / 9, 2), unit: "yd²",
                     identifier: "result.area.squareYards")
            if shape == 2 {
                WatchRow(label: "Circumference", value: WFmt.f(Area.circumference(radius: a), 2),
                         unit: "ft", identifier: "result.area.circumference")
            }
        }
    }
}

// MARK: - Takeoff · Volume

struct VolumeWatch: View {
    @EnvironmentObject private var crownFocus: CrownFocus
    @State private var shape = 0            // 0 box, 1 cylinder
    @State private var a = 10.0
    @State private var c = 8.0
    @State private var active = 0
    private let accent = Tool.volume.accent
    private let b = 10.0                    // phone default box width

    var body: some View {
        WatchToolScreen(tool: .volume) {
            let ft3 = VolumeShapeChoice.volumeFt3(index: shape, a: a, b: b, c: c)

            WatchHero(label: "Volume", value: WFmt.f(ft3, 2), unit: "ft³",
                      identifier: "result.volume.hero")
            CrownField(label: shape == 0 ? "LENGTH" : "DIAMETER",
                       value: $a, unit: "ft", step: 0.5, range: 0...1000,
                       targeted: active == 0, accent: accent, places: 1,
                       identifier: "input.volume.a")
                .onTapGesture { active = 0; crownFocus.reclaim() }
            CrownField(label: "HEIGHT", value: $c, unit: "ft", step: 0.5, range: 0...1000,
                       targeted: active == 1, accent: accent, places: 1,
                       identifier: "input.volume.c")
                .onTapGesture { active = 1; crownFocus.reclaim() }

            WatchIndexPicker(titles: VolumeShapeChoice.titles, index: $shape,
                             accent: accent, identifier: "input.volume.shape")

            WatchRow(label: "Cubic yards", value: WFmt.f(Volume.cubicFeetToYards(ft3), 3),
                     unit: "yd³", identifier: "result.volume.cubicYards")
            if shape == 0 {
                WatchPinnedRow(label: "Width", value: "10 ft", identifier: "fixed.volume")
            }
        }
    }
}

// MARK: - Materials · Roofing

struct RoofingWatch: View {
    @EnvironmentObject private var crownFocus: CrownFocus
    @State private var plan = 2000.0        // ft² footprint
    @State private var rise = 6.0           // X/12
    @State private var active = 0
    private let accent = Tool.roofing.accent
    private let waste = 10.0                // phone default

    var body: some View {
        WatchToolScreen(tool: .roofing) {
            let area = Roofing.roofArea(planAreaFt2: plan, riseIn12: rise)

            WatchHero(label: "Squares", value: WFmt.f(Roofing.squares(roofAreaFt2: area), 2),
                      unit: "sq", identifier: "result.roofing.hero")
            CrownField(label: "PLAN AREA", value: $plan, unit: "ft²", step: 50, range: 0...100000,
                       targeted: active == 0, accent: accent, places: 0,
                       identifier: "input.roofing.plan")
                .onTapGesture { active = 0; crownFocus.reclaim() }
            CrownField(label: "PITCH", value: $rise, unit: "/12", step: 1, range: 0...24,
                       targeted: active == 1, accent: accent, places: 0,
                       identifier: "input.roofing.pitch")
                .onTapGesture { active = 1; crownFocus.reclaim() }

            WatchRow(label: "+ 10% waste",
                     value: WFmt.f(Roofing.squaresWithWaste(roofAreaFt2: area, wastePct: waste), 2),
                     unit: "sq", emphasis: true, accent: accent, identifier: "result.roofing.withWaste")
            WatchRow(label: "Roof area", value: WFmt.f(area, 2), unit: "ft²",
                     identifier: "result.roofing.roofArea")
            WatchRow(label: "Pitch ×", value: WFmt.f(Roofing.pitchMultiplier(riseIn12: rise), 4),
                     identifier: "result.roofing.multiplier")
        }
    }
}

// MARK: - Materials · Estimate

struct EstimateWatch: View {
    @EnvironmentObject private var crownFocus: CrownFocus
    @State private var mode = 0             // 0 drywall, 1 paint, 2 block
    @State private var area = 1000.0
    private let accent = Tool.estimate.accent
    private let coats = 2                   // phone default

    var body: some View {
        WatchToolScreen(tool: .estimate) {
            let hero = EstimateHero.hero(mode: mode, area: area, coats: coats)

            WatchHero(label: hero.label, value: hero.value, unit: hero.unit,
                      identifier: "result.estimate.hero")
            CrownField(label: "AREA", value: $area, unit: "ft²", step: 25, range: 0...100000,
                       targeted: true, accent: accent, places: 0,
                       identifier: "input.estimate.area")
                .onTapGesture { crownFocus.reclaim() }

            WatchIndexPicker(titles: ["Drywall", "Paint", "Block"], index: $mode,
                             accent: accent, identifier: "input.estimate.mode")

            WatchRow(label: "Modular brick",
                     value: "\(Estimate.units(areaFt2: area, perFt2: Estimate.modularBrickPerFt2))",
                     unit: "brick", identifier: "result.estimate.brick")
            WatchRow(label: "CMU 8×16",
                     value: "\(Estimate.units(areaFt2: area, perFt2: Estimate.cmu8x16PerFt2))",
                     unit: "block", identifier: "result.estimate.cmu")
            if mode == 1 {
                WatchPinnedRow(label: "Coats", value: "2", identifier: "fixed.estimate")
            }
        }
    }
}

// MARK: - Materials · Miter

struct MiterWatch: View {
    @EnvironmentObject private var crownFocus: CrownFocus
    @State private var spring = 38.0
    @State private var sides = 4.0
    @State private var active = 0
    private let accent = Tool.miter.accent

    var body: some View {
        WatchToolScreen(tool: .miter) {
            let r = CompoundMiter.compound(springDeg: spring, sides: Int(sides))

            WatchHero(label: "Miter", value: WFmt.f(r.miter, 2), unit: "°",
                      identifier: "result.miter.hero")
            CrownField(label: "SPRING", value: $spring, unit: "°", step: 0.5, range: 1...89,
                       targeted: active == 0, accent: accent, places: 1,
                       identifier: "input.miter.spring")
                .onTapGesture { active = 0; crownFocus.reclaim() }
            CrownField(label: "SIDES", value: $sides, unit: "", step: 1, range: 3...24,
                       targeted: active == 1, accent: accent, places: 0,
                       identifier: "input.miter.sides")
                .onTapGesture { active = 1; crownFocus.reclaim() }

            WatchRow(label: "Bevel", value: WFmt.f(r.bevel, 2), unit: "°",
                     emphasis: true, accent: accent, identifier: "result.miter.bevel")
            WatchRow(label: "Flat miter",
                     value: WFmt.f(CompoundMiter.simpleMiterDeg(sides: Int(sides)), 2), unit: "°",
                     identifier: "result.miter.flat")
        }
    }
}

// MARK: - Materials · Lumber

struct LumberWatch: View {
    @EnvironmentObject private var crownFocus: CrownFocus
    @State private var w = 6.0
    @State private var lenFt = 10.0
    @State private var active = 0
    private let accent = Tool.lumber.accent
    private let t = 2.0                     // phone default — nominal 2x stock
    private let pieces = 1.0                // phone default

    var body: some View {
        WatchToolScreen(tool: .lumber) {
            let bf = Estimate.boardFeet(thicknessIn: t, widthIn: w, lengthFt: lenFt)

            WatchHero(label: "Board feet", value: WFmt.f(bf * pieces, 2), unit: "bf",
                      identifier: "result.lumber.hero")
            CrownField(label: "WIDTH", value: $w, unit: "in", step: 0.5, range: 0.5...48,
                       targeted: active == 0, accent: accent, places: 1,
                       identifier: "input.lumber.width")
                .onTapGesture { active = 0; crownFocus.reclaim() }
            CrownField(label: "LENGTH", value: $lenFt, unit: "ft", step: 0.5, range: 0.5...100,
                       targeted: active == 1, accent: accent, places: 1,
                       identifier: "input.lumber.length")
                .onTapGesture { active = 1; crownFocus.reclaim() }

            WatchRow(label: "Per piece", value: WFmt.f(bf, 3), unit: "bf",
                     identifier: "result.lumber.each")
            WatchPinnedRow(label: "Thick · pieces", value: "2\" · 1", identifier: "fixed.lumber")
        }
    }
}

// MARK: - Materials · Mortar

struct MortarWatch: View {
    @EnvironmentObject private var crownFocus: CrownFocus
    @State private var mode = 0             // 0 block, 1 brick, 2 grout
    @State private var count = 100.0
    @State private var wallArea = 100.0
    private let accent = Tool.mortar.accent

    var body: some View {
        WatchToolScreen(tool: .mortar) {
            let hero = MortarHero.hero(mode: mode, count: count, wallArea: wallArea)

            WatchHero(label: hero.label, value: hero.value, unit: hero.unit,
                      identifier: "result.mortar.hero")
            // Grout is priced by wall AREA, the other two by unit COUNT — two different quantities, so
            // the field switches rather than relabelling one binding.
            if mode == 2 {
                CrownField(label: "WALL AREA", value: $wallArea, unit: "ft²", step: 5, range: 0...20000,
                           targeted: true, accent: accent, places: 0,
                           identifier: "input.mortar.wallArea")
                    .onTapGesture { crownFocus.reclaim() }
            } else {
                CrownField(label: "UNITS", value: $count, unit: "", step: 5, range: 0...20000,
                           targeted: true, accent: accent, places: 0,
                           identifier: "input.mortar.count")
                    .onTapGesture { crownFocus.reclaim() }
            }

            WatchIndexPicker(titles: ["Block", "Brick", "Grout"], index: $mode,
                             accent: accent, identifier: "input.mortar.mode")

            if mode == 2 {
                WatchRow(label: "Grout volume", value: WFmt.f(Grout.cubicFeet(wallAreaFt2: wallArea), 1),
                         unit: "ft³", identifier: "result.mortar.groutVolume")
            } else {
                WatchRow(label: "Per 80 lb bag", value: mode == 0 ? "13 blk" : "37 brk",
                         identifier: "result.mortar.rate")
            }
        }
    }
}

// MARK: - Pipe · Offset

struct OffsetWatch: View {
    @EnvironmentObject private var crownFocus: CrownFocus
    @State private var setIn = 10.0
    @State private var angleIdx = 0
    private let accent = Tool.offset.accent

    var body: some View {
        WatchToolScreen(tool: .offset) {
            let angle = PipeFittingChoice.angleDeg(index: angleIdx, custom: 0)

            WatchHero(label: "Travel",
                      value: WFmt.f(PipeOffset.travelIn(setIn: setIn, fittingAngleDeg: angle), 2),
                      unit: "in", identifier: "result.offset.hero")
            CrownField(label: "SET", value: $setIn, unit: "in", step: 0.25, range: 0...480,
                       targeted: true, accent: accent, places: 2,
                       identifier: "input.offset.set")
                .onTapGesture { crownFocus.reclaim() }

            WatchIndexPicker(titles: watchFittingTitles, index: $angleIdx,
                             accent: accent, identifier: "input.offset.angle")

            WatchRow(label: "Run used",
                     value: WFmt.f(PipeOffset.runIn(setIn: setIn, fittingAngleDeg: angle), 2),
                     unit: "in", identifier: "result.offset.run")
            WatchRow(label: "Travel × (csc)",
                     value: WFmt.f(PipeOffset.travelMultiplier(fittingAngleDeg: angle), 4),
                     identifier: "result.offset.multiplier")
        }
    }
}

// MARK: - Pipe · Rolling Offset

struct RollingOffsetWatch: View {
    @EnvironmentObject private var crownFocus: CrownFocus
    @State private var setIn = 6.0
    @State private var rollIn = 8.0
    @State private var angleIdx = 0
    @State private var active = 0
    private let accent = Tool.rollingOffset.accent

    var body: some View {
        WatchToolScreen(tool: .rollingOffset) {
            let angle = PipeFittingChoice.angleDeg(index: angleIdx, custom: 0)
            let r = RollingOffset.solve(setIn: setIn, rollIn: rollIn, fittingAngleDeg: angle)

            WatchHero(label: "Travel", value: WFmt.f(r.travelIn, 2), unit: "in",
                      identifier: "result.rollingOffset.hero")
            CrownField(label: "SET", value: $setIn, unit: "in", step: 0.25, range: 0...480,
                       targeted: active == 0, accent: accent, places: 2,
                       identifier: "input.rollingOffset.set")
                .onTapGesture { active = 0; crownFocus.reclaim() }
            CrownField(label: "ROLL", value: $rollIn, unit: "in", step: 0.25, range: 0...480,
                       targeted: active == 1, accent: accent, places: 2,
                       identifier: "input.rollingOffset.roll")
                .onTapGesture { active = 1; crownFocus.reclaim() }

            WatchIndexPicker(titles: watchFittingTitles, index: $angleIdx,
                             accent: accent, identifier: "input.rollingOffset.angle")

            WatchRow(label: "True offset", value: WFmt.f(r.trueOffsetIn, 2), unit: "in",
                     emphasis: true, accent: accent, identifier: "result.rollingOffset.trueOffset")
            WatchRow(label: "Roll the fitting", value: WFmt.f(r.rollAngleDeg, 2), unit: "°",
                     identifier: "result.rollingOffset.rollAngle")
        }
    }
}

// MARK: - Pipe · Cut Length

struct CutLengthWatch: View {
    @EnvironmentObject private var crownFocus: CrownFocus
    @State private var centerToCenterIn = 24.0
    private let accent = Tool.cutLength.accent
    private let takeoutA = 1.5, takeoutB = 1.5      // phone defaults

    var body: some View {
        WatchToolScreen(tool: .cutLength) {
            let endToEnd = PipeCut.endToEndIn(centerToCenterIn: centerToCenterIn,
                                              takeoutAIn: takeoutA, takeoutBIn: takeoutB)
            let collides = PipeCut.fittingsCollide(centerToCenterIn: centerToCenterIn,
                                                  takeoutAIn: takeoutA, takeoutBIn: takeoutB)

            WatchHero(label: "End to end", value: WFmt.f(endToEnd, 2), unit: "in",
                      identifier: "result.cutLength.hero")
            CrownField(label: "CENTRE TO CENTRE", value: $centerToCenterIn, unit: "in",
                       step: 0.25, range: 0...480,
                       targeted: true, accent: accent, places: 2,
                       identifier: "input.cutLength.centreToCentre")
                .onTapGesture { crownFocus.reclaim() }

            WatchRow(label: "Total takeout", value: WFmt.f(takeoutA + takeoutB, 2), unit: "in",
                     identifier: "result.cutLength.takeout")
            // A negative cut is not a short pipe, it is two fittings in the same space. Say so.
            WatchRow(label: "Fittings", value: collides ? "COLLIDE ⚠" : "FIT",
                     emphasis: collides, accent: KC.warn, identifier: "result.cutLength.fit")
            WatchPinnedRow(label: "Takeouts", value: "1.5\" · 1.5\"", identifier: "fixed.cutLength")
        }
    }
}

// MARK: - Pipe · Grade

struct GradeWatch: View {
    @EnvironmentObject private var crownFocus: CrownFocus
    @State private var runFt  = 10.0
    @State private var fallIn = 2.5
    @State private var active = 0
    private let accent = Tool.grade.accent

    var body: some View {
        WatchToolScreen(tool: .grade) {
            let fpf = PipeGrade.fallInPerFt(fallIn: fallIn, runFeet: runFt)

            WatchHero(label: "Grade", value: WFmt.f(PipeGrade.percent(fallInPerFt: fpf), 2),
                      unit: "%", identifier: "result.grade.hero")
            CrownField(label: "RUN", value: $runFt, unit: "ft", step: 0.5, range: 0.5...1000,
                       targeted: active == 0, accent: accent, places: 1,
                       identifier: "input.grade.run")
                .onTapGesture { active = 0; crownFocus.reclaim() }
            CrownField(label: "FALL", value: $fallIn, unit: "in", step: 0.125, range: 0...240,
                       targeted: active == 1, accent: accent, places: 3,
                       identifier: "input.grade.fall")
                .onTapGesture { active = 1; crownFocus.reclaim() }

            WatchRow(label: "Fall / ft", value: WFmt.f(fpf, 3), unit: "in/ft",
                     emphasis: true, accent: accent, identifier: "result.grade.fallPerFt")
            WatchRow(label: "Ratio", value: "1:" + WFmt.f(PipeGrade.ratioDenominator(fallInPerFt: fpf), 0),
                     identifier: "result.grade.ratio")
            WatchRow(label: "Angle", value: WFmt.f(PipeGrade.degrees(fallInPerFt: fpf), 2), unit: "°",
                     identifier: "result.grade.angle")
        }
    }
}

// MARK: - Convert · Units

struct ConvertWatch: View {
    @EnvironmentObject private var crownFocus: CrownFocus
    @State private var value = 1.0
    // Bind the units themselves — an index into `allCases` is a silent mis-conversion waiting to
    // happen (`firstIndex(of:) ?? 0` would quietly fall back to millimetres).
    @State private var from: LengthUnit = .foot
    @State private var to: LengthUnit = .meter
    private let accent = Tool.units.accent

    var body: some View {
        WatchToolScreen(tool: .units) {
            WatchHero(label: "Result", value: WFmt.f(Units.convert(value, from: from, to: to), 4),
                      unit: to.symbol, identifier: "result.units.hero")
            CrownField(label: "VALUE", value: $value, unit: from.symbol, step: 0.1, range: 0...100000,
                       targeted: true, accent: accent, places: 2,
                       identifier: "input.units.value")
                .onTapGesture { crownFocus.reclaim() }

            HStack(spacing: 5) {
                unitPicker("FROM", selection: $from)
                Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(KCW.inkFaint)
                unitPicker("TO", selection: $to)
            }
        }
    }

    private func unitPicker(_ label: String, selection: Binding<LengthUnit>) -> some View {
        Picker(label, selection: selection) {
            ForEach(LengthUnit.allCases) { Text($0.symbol).tag($0) }
        }
        .watchPicker(tint: accent, identifier: "input.units." + label.lowercased())
        .onChange(of: selection.wrappedValue) { _, _ in crownFocus.reclaim() }
    }
}

// MARK: - Previews  (40 mm is the real floor — 162 pt, not 41 mm)

#Preview("Rafter") { NavigationStack { RafterWatch() }.environmentObject(CrownFocus()) }
#Preview("Pavers") { NavigationStack { PaversWatch() }.environmentObject(CrownFocus()) }
#Preview("Concrete") { NavigationStack { ConcreteWatch() }.environmentObject(CrownFocus()) }
#Preview("Convert") { NavigationStack { ConvertWatch() }.environmentObject(CrownFocus()) }
