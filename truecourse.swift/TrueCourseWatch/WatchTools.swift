import SwiftUI
import WindKit
import AirspeedKit
import AltitudeKit
import NavKit
import FuelKit
import ClimbDescentKit
import WeightBalanceKit
import ConvertKit
import TimeKit

// The 9 tool screens, full sub-screen parity with the phone. Each: a WatchSegmented sub-screen
// switch (where the phone has one) + tap-to-target CrownFields + one off-white HeroReadout + compact
// stats. Math from the oracle-tested Kits. RULE: every segment switch / picker / button calls
// `crownFocus.reclaim()` so it hands the Digital Crown back to the active field.

/// A CrownField wired to a screen's shared `active` index — tap it to make it the crown target.
private struct ActiveField: View {
    @EnvironmentObject private var crownFocus: CrownFocus
    let label: String
    @Binding var value: Double
    var unit: String = ""
    let step: Double
    let range: ClosedRange<Double>
    @Binding var active: Int
    let index: Int
    let accent: Color
    var places: Int = 0
    var body: some View {
        CrownField(label: label, value: $value, unit: unit, step: step, range: range,
                   targeted: active == index, accent: accent, places: places)
            .onTapGesture { active = index; crownFocus.reclaim() }
    }
}

// MARK: - Wind

struct WindWatch: View {
    @Environment(\.tc) private var tc
    @EnvironmentObject private var crownFocus: CrownFocus
    @State private var screen = 0
    @State private var active = 0
    @State private var course = 90.0
    @State private var tas = 120.0
    @State private var windDir = 180.0
    @State private var windSpd = 30.0
    @State private var runway = 90.0
    @State private var heading = 105.0
    @State private var gs = 116.0
    private var a: Color { tc.accent(.wind) }

    var body: some View {
        WatchToolScreen(title: "Wind Triangle") {
            WatchSegmented(titles: ["Solve", "Comp", "Derive"], selection: $screen, accent: a) {
                active = 0; crownFocus.reclaim()
            }
            switch screen {
            case 0:
                ActiveField(label: "Course", value: $course, unit: "°T", step: 1, range: Bounds.bearingDeg, active: $active, index: 0, accent: a)
                ActiveField(label: "TAS", value: $tas, unit: "kt", step: 1, range: Bounds.airspeedKt, active: $active, index: 1, accent: a)
                ActiveField(label: "Wind from", value: $windDir, unit: "°T", step: 1, range: Bounds.bearingDeg, active: $active, index: 2, accent: a)
                ActiveField(label: "Wind spd", value: $windSpd, unit: "kt", step: 1, range: Bounds.windSpeedKt, active: $active, index: 3, accent: a)
                let s = Wind.solution(courseDeg: course, tasKt: tas, windDirDeg: windDir, windSpeedKt: windSpd)
                HeroReadout(label: "Heading", value: s.map { Fmt.heading($0.headingDeg) } ?? "—", accent: a)
                HStack(spacing: 6) {
                    WatchStat(label: "GS", value: s.map { Fmt.i($0.gsKt) + " kt" } ?? "—")
                    WatchStat(label: "WCA", value: s.map { Fmt.signed($0.wcaDeg, 0) + "°" } ?? "—")
                }
            case 1:
                ActiveField(label: "Runway", value: $runway, unit: "°", step: 1, range: Bounds.bearingDeg, active: $active, index: 0, accent: a)
                ActiveField(label: "Wind from", value: $windDir, unit: "°T", step: 1, range: Bounds.bearingDeg, active: $active, index: 1, accent: a)
                ActiveField(label: "Wind spd", value: $windSpd, unit: "kt", step: 1, range: Bounds.windSpeedKt, active: $active, index: 2, accent: a)
                let c = Wind.components(runwayHeadingDeg: runway, windDirDeg: windDir, windSpeedKt: windSpd)
                HeroReadout(label: c.crosswindKt >= 0 ? "Crosswind R" : "Crosswind L", value: Fmt.i(abs(c.crosswindKt)), unit: "kt", accent: a)
                WatchStat(label: c.headwindKt >= 0 ? "Headwind" : "Tailwind", value: Fmt.i(abs(c.headwindKt)) + " kt")
            default:
                ActiveField(label: "Course", value: $course, unit: "°T", step: 1, range: Bounds.bearingDeg, active: $active, index: 0, accent: a)
                ActiveField(label: "Heading", value: $heading, unit: "°T", step: 1, range: Bounds.bearingDeg, active: $active, index: 1, accent: a)
                ActiveField(label: "TAS", value: $tas, unit: "kt", step: 1, range: Bounds.airspeedKt, active: $active, index: 2, accent: a)
                ActiveField(label: "GS", value: $gs, unit: "kt", step: 1, range: Bounds.groundspeedKt, active: $active, index: 3, accent: a)
                let d = Wind.derive(courseDeg: course, headingDeg: heading, tasKt: tas, gsKt: gs)
                HeroReadout(label: "Wind from", value: Fmt.heading(d.windDirDeg), accent: a)
                WatchStat(label: "Wind speed", value: Fmt.i(d.windSpeedKt) + " kt")
            }
        }
    }
}

// MARK: - Airspeed

struct AirspeedWatch: View {
    @Environment(\.tc) private var tc
    @EnvironmentObject private var crownFocus: CrownFocus
    @State private var screen = 0
    @State private var active = 0
    @State private var cas = 120.0
    @State private var pa = 8000.0
    @State private var oat = 0.0
    @State private var tas = 450.0
    @State private var oatM = -50.0
    private var a: Color { tc.accent(.airspeed) }

    var body: some View {
        WatchToolScreen(title: "True Airspeed") {
            WatchSegmented(titles: ["TAS", "Mach"], selection: $screen, accent: a) { active = 0; crownFocus.reclaim() }
            if screen == 0 {
                ActiveField(label: "CAS", value: $cas, unit: "kt", step: 1, range: Bounds.airspeedKt, active: $active, index: 0, accent: a)
                ActiveField(label: "Press alt", value: $pa, unit: "ft", step: 100, range: Bounds.altitudeFt, active: $active, index: 1, accent: a)
                ActiveField(label: "OAT", value: $oat, unit: "°C", step: 1, range: Bounds.temperatureC, active: $active, index: 2, accent: a)
                HeroReadout(label: "True airspeed", value: Fmt.i(Airspeed.tas(casKt: cas, pressureAltFt: pa, oatC: oat)), unit: "kt", accent: a)
            } else {
                ActiveField(label: "TAS", value: $tas, unit: "kt", step: 1, range: Bounds.airspeedKt, active: $active, index: 0, accent: a)
                ActiveField(label: "OAT", value: $oatM, unit: "°C", step: 1, range: Bounds.temperatureC, active: $active, index: 1, accent: a)
                HeroReadout(label: "Mach", value: Fmt.f(Airspeed.mach(tasKt: tas, oatC: oatM), 3), accent: a)
                WatchStat(label: "Speed of sound", value: Fmt.i(Airspeed.speedOfSoundKt(oatC: oatM)) + " kt")
            }
        }
    }
}

// MARK: - Altitude

struct AltitudeWatch: View {
    @Environment(\.tc) private var tc
    @EnvironmentObject private var crownFocus: CrownFocus
    @State private var screen = 0
    @State private var active = 0
    @State private var pa = 5000.0
    @State private var oat = 25.0
    @State private var indAlt = 5500.0
    @State private var altimeter = 29.92
    @State private var temp = 25.0
    @State private var dewpoint = 15.0
    @State private var elevation = 0.0
    @State private var gs = 100.0
    private var a: Color { tc.accent(.altitude) }

    var body: some View {
        WatchToolScreen(title: "Altitude") {
            WatchSegmented(titles: ["Dens", "Press", "Env"], selection: $screen, accent: a) { active = 0; crownFocus.reclaim() }
            switch screen {
            case 0:
                ActiveField(label: "Press alt", value: $pa, unit: "ft", step: 100, range: Bounds.altitudeFt, active: $active, index: 0, accent: a)
                ActiveField(label: "OAT", value: $oat, unit: "°C", step: 1, range: Bounds.temperatureC, active: $active, index: 1, accent: a)
                HeroReadout(label: "Density altitude", value: Fmt.i(Altitude.densityAltitudeFt(pressureAltFt: pa, oatC: oat)), unit: "ft", accent: a)
                WatchStat(label: "ISA dev", value: Fmt.signed(oat - Altitude.isaTempC(altitudeFt: pa), 0) + "°C")
            case 1:
                ActiveField(label: "Ind alt", value: $indAlt, unit: "ft", step: 100, range: Bounds.altitudeFt, active: $active, index: 0, accent: a)
                ActiveField(label: "Altimeter", value: $altimeter, unit: "inHg", step: 0.01, range: Bounds.altimeterInHg, active: $active, index: 1, accent: a, places: 2)
                HeroReadout(label: "Pressure altitude", value: Fmt.i(Altitude.pressureAltitudeFt(indicatedAltFt: indAlt, altimeterInHg: altimeter)), unit: "ft", accent: a)
            default:
                ActiveField(label: "Temp", value: $temp, unit: "°C", step: 1, range: Bounds.temperatureC, active: $active, index: 0, accent: a)
                ActiveField(label: "Dew point", value: $dewpoint, unit: "°C", step: 1, range: Bounds.temperatureC, active: $active, index: 1, accent: a)
                ActiveField(label: "Elevation", value: $elevation, unit: "ft", step: 100, range: Bounds.elevationFt, active: $active, index: 2, accent: a)
                ActiveField(label: "GS", value: $gs, unit: "kt", step: 1, range: Bounds.groundspeedKt, active: $active, index: 3, accent: a)
                HeroReadout(label: "Cloud base", value: Fmt.i(Altitude.cloudBaseFt(tempC: temp, dewpointC: dewpoint)), unit: "ft AGL", accent: a)
                HStack(spacing: 6) {
                    WatchStat(label: "Freezing", value: Fmt.i(Altitude.freezingLevelFt(surfaceTempC: temp, elevationFt: elevation)) + " ft")
                    WatchStat(label: "Pivotal", value: Fmt.i(Altitude.pivotalAltitudeFt(gsKt: gs)) + " ft")
                }
            }
        }
    }
}

// MARK: - Nav

struct NavWatch: View {
    @Environment(\.tc) private var tc
    @EnvironmentObject private var crownFocus: CrownFocus
    @State private var screen = 0
    @State private var active = 0
    @State private var dist = 150.0
    @State private var gs = 120.0
    @State private var time = 75.0
    private var a: Color { tc.accent(.nav) }

    var body: some View {
        WatchToolScreen(title: "Nav Log") {
            WatchSegmented(titles: ["Time", "Dist", "Speed"], selection: $screen, accent: a) { active = 0; crownFocus.reclaim() }
            switch screen {
            case 0:
                ActiveField(label: "Distance", value: $dist, unit: "nm", step: 1, range: Bounds.distanceNm, active: $active, index: 0, accent: a)
                ActiveField(label: "Groundspeed", value: $gs, unit: "kt", step: 1, range: Bounds.groundspeedKt, active: $active, index: 1, accent: a)
                HeroReadout(label: "Time enroute", value: Fmt.minutesSeconds(Nav.timeMin(distanceNm: dist, gsKt: gs)), accent: a)
            case 1:
                ActiveField(label: "Groundspeed", value: $gs, unit: "kt", step: 1, range: Bounds.groundspeedKt, active: $active, index: 0, accent: a)
                ActiveField(label: "Time", value: $time, unit: "min", step: 1, range: Bounds.timeMin, active: $active, index: 1, accent: a)
                HeroReadout(label: "Distance", value: Fmt.i(Nav.distanceNm(gsKt: gs, timeMin: time)), unit: "nm", accent: a)
            default:
                ActiveField(label: "Distance", value: $dist, unit: "nm", step: 1, range: Bounds.distanceNm, active: $active, index: 0, accent: a)
                ActiveField(label: "Time", value: $time, unit: "min", step: 1, range: Bounds.timeMin, active: $active, index: 1, accent: a)
                HeroReadout(label: "Groundspeed", value: Fmt.i(Nav.groundspeedKt(distanceNm: dist, timeMin: time)), unit: "kt", accent: a)
            }
        }
    }
}

// MARK: - Fuel

struct FuelWatch: View {
    @Environment(\.tc) private var tc
    @EnvironmentObject private var crownFocus: CrownFocus
    @State private var screen = 0
    @State private var active = 0
    @State private var gph = 10.0
    @State private var timeHr = 2.5
    @State private var fuelGal = 40.0
    @State private var gs = 120.0
    private var a: Color { tc.accent(.fuel) }

    var body: some View {
        WatchToolScreen(title: "Fuel") {
            WatchSegmented(titles: ["Req", "Endur", "Range"], selection: $screen, accent: a) { active = 0; crownFocus.reclaim() }
            switch screen {
            case 0:
                ActiveField(label: "Burn rate", value: $gph, unit: "gph", step: 0.5, range: Bounds.fuelGph, active: $active, index: 0, accent: a, places: 1)
                ActiveField(label: "Time", value: $timeHr, unit: "h", step: 0.1, range: Bounds.timeHr, active: $active, index: 1, accent: a, places: 1)
                HeroReadout(label: "Fuel burned", value: Fmt.f(Fuel.requiredGal(gph: gph, timeHr: timeHr), 1), unit: "gal", accent: a)
                WatchStat(label: "Weight (avgas)", value: Fmt.i(Fuel.requiredGal(gph: gph, timeHr: timeHr) * Convert.avgasGalToLb(1)) + " lb")
            case 1:
                ActiveField(label: "Fuel aboard", value: $fuelGal, unit: "gal", step: 1, range: Bounds.fuelGal, active: $active, index: 0, accent: a)
                ActiveField(label: "Burn rate", value: $gph, unit: "gph", step: 0.5, range: Bounds.fuelGph, active: $active, index: 1, accent: a, places: 1)
                HeroReadout(label: "Endurance", value: Fmt.hoursMinutes(Fuel.enduranceHr(fuelGal: fuelGal, gph: gph)), accent: a)
            default:
                ActiveField(label: "Groundspeed", value: $gs, unit: "kt", step: 1, range: Bounds.groundspeedKt, active: $active, index: 0, accent: a)
                ActiveField(label: "Burn rate", value: $gph, unit: "gph", step: 0.5, range: Bounds.fuelGph, active: $active, index: 1, accent: a, places: 1)
                ActiveField(label: "Fuel aboard", value: $fuelGal, unit: "gal", step: 1, range: Bounds.fuelGal, active: $active, index: 2, accent: a)
                let spec = Fuel.specificRangeNmPerGal(gsKt: gs, gph: gph)
                HeroReadout(label: "Specific range", value: Fmt.f(spec, 1), unit: "nm/gal", accent: a)
                WatchStat(label: "Still-air range", value: Fmt.i(spec * fuelGal) + " nm")
            }
        }
    }
}

// MARK: - Climb / Descent

struct ClimbWatch: View {
    @Environment(\.tc) private var tc
    @EnvironmentObject private var crownFocus: CrownFocus
    @State private var screen = 0
    @State private var active = 0
    @State private var altToLose = 3000.0
    @State private var dist = 10.0
    @State private var gs = 120.0
    @State private var gradient = 300.0
    @State private var gsG = 90.0
    @State private var glideRatio = 9.0
    @State private var height = 5000.0
    private var a: Color { tc.accent(.climb) }

    var body: some View {
        WatchToolScreen(title: "Climb & Descent") {
            WatchSegmented(titles: ["Desc", "Grad", "Glide"], selection: $screen, accent: a) { active = 0; crownFocus.reclaim() }
            switch screen {
            case 0:
                ActiveField(label: "Alt to lose", value: $altToLose, unit: "ft", step: 100, range: Bounds.heightFt, active: $active, index: 0, accent: a)
                ActiveField(label: "Distance", value: $dist, unit: "nm", step: 1, range: Bounds.distanceNm, active: $active, index: 1, accent: a)
                ActiveField(label: "Groundspeed", value: $gs, unit: "kt", step: 1, range: Bounds.groundspeedKt, active: $active, index: 2, accent: a)
                HeroReadout(label: "Descent rate", value: Fmt.i(ClimbDescent.descentRateFpm(altitudeToLoseFt: altToLose, distanceNm: dist, gsKt: gs)), unit: "fpm", accent: a)
            case 1:
                ActiveField(label: "Gradient", value: $gradient, unit: "ft/nm", step: 10, range: Bounds.climbGradientFtPerNm, active: $active, index: 0, accent: a)
                ActiveField(label: "Groundspeed", value: $gsG, unit: "kt", step: 1, range: Bounds.groundspeedKt, active: $active, index: 1, accent: a)
                HeroReadout(label: "Climb rate", value: Fmt.i(ClimbDescent.rateFpm(gradientFtPerNm: gradient, gsKt: gsG)), unit: "fpm", accent: a)
                HStack(spacing: 6) {
                    WatchStat(label: "Gradient", value: Fmt.f(ClimbDescent.gradientPercent(ftPerNm: gradient), 2) + "%")
                    WatchStat(label: "Angle", value: Fmt.f(ClimbDescent.gradientDegrees(ftPerNm: gradient), 2) + "°")
                }
            default:
                ActiveField(label: "Glide ratio", value: $glideRatio, unit: ":1", step: 1, range: Bounds.glideRatio, active: $active, index: 0, accent: a)
                ActiveField(label: "Height", value: $height, unit: "ft AGL", step: 100, range: Bounds.heightFt, active: $active, index: 1, accent: a)
                HeroReadout(label: "Glide distance", value: Fmt.f(ClimbDescent.glideDistanceNm(glideRatio: glideRatio, heightFt: height), 1), unit: "nm", accent: a)
            }
        }
    }
}

// MARK: - Weight & Balance (4 crown station weights → CG + verdict; envelope = IN/OUT badge)

struct WBWatch: View {
    @Environment(\.tc) private var tc
    @EnvironmentObject private var crownFocus: CrownFocus
    @State private var screen = 0
    @State private var active = 0
    @State private var wEmpty = 1000.0
    @State private var wFront = 340.0
    @State private var wFuel = 180.0
    @State private var wBag = 20.0
    private let arms = (empty: 36.0, front: 37.0, fuel: 48.0, bag: 95.0)
    private let envelope = [
        EnvelopePoint(cgIn: 35.0, weightLb: 1500), EnvelopePoint(cgIn: 41.0, weightLb: 2550),
        EnvelopePoint(cgIn: 47.3, weightLb: 2550), EnvelopePoint(cgIn: 47.3, weightLb: 1500),
    ]
    private var a: Color { tc.accent(.wb) }
    private var stations: [Station] {
        [Station(id: 0, name: "Empty", weightLb: wEmpty, armIn: arms.empty),
         Station(id: 1, name: "Front", weightLb: wFront, armIn: arms.front),
         Station(id: 2, name: "Fuel",  weightLb: wFuel,  armIn: arms.fuel),
         Station(id: 3, name: "Baggage", weightLb: wBag, armIn: arms.bag)]
    }

    var body: some View {
        WatchToolScreen(title: "Weight & Balance") {
            WatchSegmented(titles: ["Load", "Envelope"], selection: $screen, accent: a) { active = 0; crownFocus.reclaim() }
            let r = WeightBalance.cg(stations: stations)
            let inside = WeightBalance.withinEnvelope(cgIn: r.cgIn, weightLb: r.totalWeightLb, envelope: envelope)
            if screen == 0 {
                ActiveField(label: "Empty @36", value: $wEmpty, unit: "lb", step: 10, range: Bounds.stationWeightLb, active: $active, index: 0, accent: a)
                ActiveField(label: "Front @37", value: $wFront, unit: "lb", step: 10, range: Bounds.stationWeightLb, active: $active, index: 1, accent: a)
                ActiveField(label: "Fuel @48", value: $wFuel, unit: "lb", step: 5, range: Bounds.stationWeightLb, active: $active, index: 2, accent: a)
                ActiveField(label: "Baggage @95", value: $wBag, unit: "lb", step: 5, range: Bounds.stationWeightLb, active: $active, index: 3, accent: a)
                HeroReadout(label: "Centre of gravity", value: Fmt.f(r.cgIn, 1), unit: "in", accent: a)
                HStack(spacing: 6) {
                    WatchStat(label: "Gross", value: Fmt.i(r.totalWeightLb) + " lb")
                    verdictBadge(inside)
                }
            } else {
                HeroReadout(label: "Centre of gravity", value: Fmt.f(r.cgIn, 1), unit: "in", accent: a)
                WatchStat(label: "Gross", value: Fmt.i(r.totalWeightLb) + " lb")
                verdictBadge(inside)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder private func verdictBadge(_ inside: Bool) -> some View {
        Text(inside ? "WITHIN LIMITS" : "OUT OF LIMITS")
            .font(.system(.caption2, design: .monospaced).weight(.semibold)).tracking(0.6)
            .foregroundStyle(inside ? tc.normal : tc.warning)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background((inside ? tc.normal : tc.warning).opacity(0.14), in: .rect(cornerRadius: 11))
            .accessibilityIdentifier("verdict.envelope")
    }
}

// MARK: - Convert (category + from-unit pickers + crown value)

struct ConvertWatch: View {
    @Environment(\.tc) private var tc
    // Manual crown focus: one @FocusState for all three controls. The crown drives whichever is
    // focused; focus moves ONLY when the user taps a control — never on a value/category/unit change
    // (that auto-reclaim was the focus-steal bug). `ConvertFocus` owns the policy and is unit-tested.
    @StateObject private var m = ConvertFocus()
    @FocusState private var focus: ConvertField?
    private var a: Color { tc.accent(.convert) }

    // (name, decimals, [(unit, toBase, fromBase)]) — the same tables as the phone's ConvertKit wiring.
    private let cats: [(name: String, dec: Int, units: [(String, (Double) -> Double, (Double) -> Double)])] = [
        ("Temp", 1, [("°C", { $0 }, { $0 }), ("°F", Convert.fToC, Convert.cToF)]),
        ("Dist", 2, [("nm", { $0 }, { $0 }), ("sm", Convert.smToNm, Convert.nmToSm), ("km", Convert.kmToNm, Convert.nmToKm)]),
        ("Alt", 1, [("ft", { $0 }, { $0 }), ("m", Convert.mToFt, Convert.ftToM)]),
        ("Speed", 1, [("kt", { $0 }, { $0 }), ("mph", Convert.mphToKt, Convert.ktToMph)]),
        ("Weight", 1, [("lb", { $0 }, { $0 }), ("kg", Convert.kgToLb, Convert.lbToKg)]),
        ("Fuel", 1, [("gal", { $0 }, { $0 }), ("L", Convert.litreToGal, Convert.galToLitre), ("lb", Convert.avgasLbToGal, Convert.avgasGalToLb)]),
        ("Climb", 2, [("ft/nm", { $0 }, { $0 }), ("%", Convert.percentToFtPerNm, Convert.ftPerNmToPercent), ("°", Convert.degreesToFtPerNm, Convert.ftPerNmToDegrees)]),
    ]

    var body: some View {
        WatchToolScreen(title: "Convert") {
            let cat = cats[m.catIdx]
            let from = cat.units[min(m.unitIdx, cat.units.count - 1)]
            let base = from.1(m.value)
            // Setters route through the model so a crown tick can't move focus. `.focused(…, equals:)`
            // reflects taps back into the model via the `focus` sync below; scrolling keeps focus put.
            Picker("Category", selection: Binding(get: { m.catIdx }, set: { m.setCategory($0) })) {
                ForEach(cats.indices, id: \.self) { Text(cats[$0].name).tag($0) }
            }
            .frame(minHeight: 44).tint(a).labelsHidden()
            .focused($focus, equals: .category)
            Picker("From", selection: Binding(get: { m.unitIdx }, set: { m.setUnit($0) })) {
                ForEach(cat.units.indices, id: \.self) { Text(cat.units[$0].0).tag($0) }
            }
            .frame(minHeight: 44).tint(a).labelsHidden()
            .focused($focus, equals: .unit)
            valueCard(dec: cat.dec, unit: from.0)
            // One hero = the first other-unit conversion; any remaining units are compact stats.
            let others = cat.units.indices.filter { $0 != m.unitIdx }
            if let first = others.first {
                HeroReadout(label: cat.units[first].0, value: Fmt.f(cat.units[first].2(base), cat.dec), accent: a)
            }
            if others.count > 1 {
                HStack(spacing: 6) {
                    ForEach(others.dropFirst(), id: \.self) { i in
                        WatchStat(label: cat.units[i].0, value: Fmt.f(cat.units[i].2(base), cat.dec))
                    }
                }
            }
        }
        // Two-way mirror: a tap changes @FocusState → record it as the manual switch; the model never
        // moves focus on its own, so scrolling any control leaves the crown where the user put it.
        .onAppear { focus = m.field }
        .onChange(of: focus) { _, f in if let f { m.focus(f) } }
        .onChange(of: m.field) { _, f in if focus != f { focus = f } }
    }

    // The Value card — a crown target sharing the SAME @FocusState as the pickers, so exactly one
    // control holds the crown and tapping switches between them.
    @ViewBuilder private func valueCard(dec: Int, unit: String) -> some View {
        let targeted = (focus == .value)
        VStack(alignment: .leading, spacing: 1) {
            Text("VALUE")
                .font(.system(size: 9, design: .monospaced).weight(.semibold)).tracking(0.8)
                .foregroundStyle(tc.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Fmt.f(m.value, dec))
                    .font(.system(.title3, design: .monospaced).weight(.semibold)).monospacedDigit()
                    .foregroundStyle(tc.textPrimary)
                Text(unit).font(.system(size: 9, design: .monospaced)).foregroundStyle(tc.textTertiary)
                Spacer(minLength: 2)
                if targeted {
                    Image(systemName: "digitalcrown.arrow.clockwise.fill")
                        .font(.system(size: 9)).foregroundStyle(a)
                }
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(tc.surfaceRaised, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(targeted ? a : tc.hairline, lineWidth: targeted ? 1.5 : 1))
        .focusable()
        .focused($focus, equals: .value)
        .digitalCrownRotation(Binding(get: { m.value }, set: { m.setValue($0) }),
                              from: 0, through: 100000, by: 1, sensitivity: .medium,
                              isContinuous: false, isHapticFeedbackEnabled: true)
        .onTapGesture { focus = .value }
        .accessibilityLabel(Text("Value"))
        .accessibilityValue(Text("\(Fmt.f(m.value, dec)) \(unit)"))
    }
}

// MARK: - Timer (live Zulu + local clock; crown-set countdown)

struct TimerWatch: View {
    @Environment(\.tc) private var tc
    @EnvironmentObject private var crownFocus: CrownFocus
    @State private var durationMin = 5.0
    @State private var endDate: Date? = nil
    private var a: Color { tc.accent(.timer) }

    var body: some View {
        WatchToolScreen(title: "Clock & Timer") {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                VStack(spacing: 7) {
                    HStack(spacing: 6) {
                        WatchStat(label: "Zulu", value: clock(ctx.date, utc: true))
                        WatchStat(label: "Local", value: clock(ctx.date, utc: false))
                    }
                    if let end = endDate {
                        let remaining = max(0, end.timeIntervalSince(ctx.date))
                        HeroReadout(label: "Remaining", value: Fmt.minutesSeconds(remaining / 60), accent: a)
                    } else {
                        HeroReadout(label: "Countdown", value: Fmt.minutesSeconds(durationMin), accent: a)
                    }
                }
            }
            CrownField(label: "Duration", value: $durationMin, unit: "min", step: 1, range: Bounds.durationMin,
                       targeted: endDate == nil, accent: a)
                .onTapGesture { crownFocus.reclaim() }
            HStack(spacing: 6) {
                Button(endDate == nil ? "Start" : "Stop") {
                    endDate = endDate == nil ? Date().addingTimeInterval(durationMin * 60) : nil
                    crownFocus.reclaim()
                }
                .tint(a)
                Button("Reset") { endDate = nil; crownFocus.reclaim() }
                    .tint(tc.textTertiary)
            }
            .font(.system(.footnote, design: .monospaced).weight(.semibold))
        }
    }

    private func clock(_ date: Date, utc: Bool) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        if utc { f.timeZone = TimeZone(identifier: "UTC") }
        return f.string(from: date)
    }
}
