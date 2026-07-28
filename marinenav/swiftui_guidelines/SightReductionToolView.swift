import SwiftUI
import CelestialNavKit

/// Celestial sight reduction. ZERO math here: dip, refraction, ha, Ho, LHA and
/// the Marcq Saint-Hilaire reduction all come from `Navigation`. `dm` and `dms`
/// only assemble and format degrees and minutes.
@MainActor
final class SightReductionViewModel: ObservableObject {
    // Sextant
    @Published var sextantDeg: Double = 34
    @Published var sextantMin: Double = 54.6
    @Published var indexArcmin: Double = 2.0
    @Published var indexOffTheArc: Bool = true
    @Published var heightOfEyeFeet: Double = 40

    // Almanac
    @Published var ghaDeg: Double = 153
    @Published var ghaMin: Double = 47.9
    @Published var decDeg: Double = 74
    @Published var decMin: Double = 3.4

    // Assumed position
    @Published var assumedLat: Double = 36
    @Published var assumedLonWest: Double = 66.798333

    var indexCorrection: Navigation.IndexCorrection {
        indexOffTheArc ? .offTheArc(arcmin: indexArcmin) : .onTheArc(arcmin: indexArcmin)
    }

    var hs: Double { dm(sextantDeg, sextantMin) }
    var gha: Double { dm(ghaDeg, ghaMin) }
    var dec: Double { dm(decDeg, decMin) }

    var dip: Double { Navigation.dipArcmin(heightOfEyeFeet: heightOfEyeFeet) }

    var apparentAltitude: Double {
        Navigation.apparentAltitude(sextantHs: hs, indexCorrection: indexCorrection,
                                    heightOfEyeFeet: heightOfEyeFeet)
    }

    var refraction: Double {
        Navigation.refractionArcmin(apparentAltitudeDeg: apparentAltitude)
    }

    var observedAltitude: Double {
        Navigation.observedAltitude(sextantHs: hs, indexCorrection: indexCorrection,
                                    heightOfEyeFeet: heightOfEyeFeet)
    }

    var reduction: Navigation.Reduction {
        Navigation.reduce(observedHo: observedAltitude, gha: gha, dec: dec,
                          assumedLat: assumedLat, assumedLonEast: -assumedLonWest)
    }

    var localHourAngle: Double {
        Navigation.localHourAngle(gha: gha, assumedLonEast: -assumedLonWest)
    }

    func format(_ v: Double, _ digits: Int = 2) -> String { String(format: "%.\(digits)f", v) }

    /// Degrees as `dd° mm.m′`, the form navigators read.
    func dms(_ v: Double) -> String {
        let sign = v < 0 ? "-" : ""
        let a = abs(v)
        let d = floor(a)
        let m = (a - d) * 60
        return String(format: "%@%.0f° %.1f′", sign, d, m)
    }

    /// The index correction as applied, signed for the sight form.
    var indexCorrectionSigned: String {
        String(format: "%@%.1f′", indexOffTheArc ? "+" : "−", indexArcmin)
    }
}

struct SightReductionToolView: View {
    @StateObject private var model = SightReductionViewModel()
    @Environment(\.marine) private var theme

    var body: some View {
        ToolScreen(tool: .sightReduction,
                   badges: ["Offline", "Bowditch-pinned", "No subscription"]) {
            ToolSection(title: "Sextant") {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sextant altitude Hs")
                            .font(MarineType.label)
                            .foregroundStyle(theme.palette.ink)
                        Text("0…90° · 0…59.9′")
                            .font(MarineType.mono10)
                            .foregroundStyle(theme.palette.inkDim)
                    }
                    Spacer(minLength: 8)
                    degreeField($model.sextantDeg, range: 0...90, suffix: "°",
                                identifier: "input.hsDeg")
                    degreeField($model.sextantMin, range: 0...59.9, suffix: "′",
                                fraction: 0...1, identifier: "input.hsMin")
                }
                .frame(minHeight: MarineMetrics.controlHeight)
                .padding(.horizontal, 12)

                MarineDivider()

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Index error").font(MarineType.label)
                            .foregroundStyle(theme.palette.ink)
                        Text("0 … 10′").font(MarineType.mono10)
                            .foregroundStyle(theme.palette.inkDim)
                    }
                    Spacer(minLength: 8)
                    degreeField($model.indexArcmin, range: 0...10, suffix: "′",
                                fraction: 0...1, identifier: "input.indexError")
                    MarineSegmented(selection: $model.indexOffTheArc,
                                    options: [(true, "Off arc"), (false, "On arc")])
                        .frame(width: 140)
                        .accessibilityIdentifier("input.indexSide")
                }
                .frame(minHeight: MarineMetrics.controlHeight)
                .padding(.horizontal, 12)

                MarineDivider()

                NumberField(label: "Height of eye", value: $model.heightOfEyeFeet,
                            range: 0...300, unit: "ft", step: 1, fraction: 0...1,
                            identifier: "input.heightOfEye")
            }

            sightForm

            ToolSection(title: "Almanac") {
                HStack(spacing: 8) {
                    Text("GHA").font(MarineType.label).foregroundStyle(theme.palette.inkDim)
                    Spacer(minLength: 8)
                    degreeField($model.ghaDeg, range: 0...359, suffix: "°",
                                identifier: "input.ghaDeg")
                    degreeField($model.ghaMin, range: 0...59.9, suffix: "′",
                                fraction: 0...1, identifier: "input.ghaMin")
                }
                .frame(minHeight: MarineMetrics.controlHeight)
                .padding(.horizontal, 12)
                MarineDivider()
                HStack(spacing: 8) {
                    Text("Declination").font(MarineType.label)
                        .foregroundStyle(theme.palette.inkDim)
                    Spacer(minLength: 8)
                    degreeField($model.decDeg, range: -90...90, suffix: "°",
                                identifier: "input.decDeg")
                    degreeField($model.decMin, range: 0...59.9, suffix: "′",
                                fraction: 0...1, identifier: "input.decMin")
                }
                .frame(minHeight: MarineMetrics.controlHeight)
                .padding(.horizontal, 12)
            }

            ToolSection(title: "Assumed position") {
                NumberField(label: "Latitude", value: $model.assumedLat, range: -90...90,
                            step: 0.1, fraction: 0...4, identifier: "input.assumedLat")
                MarineDivider()
                NumberField(label: "Longitude W", value: $model.assumedLonWest,
                            range: -180...180, step: 0.1, fraction: 0...4,
                            identifier: "input.assumedLon")
                MarineDivider()
                ResultRow(label: "LHA", value: model.format(model.localHourAngle, 1),
                          unit: "°", identifier: "result.lha")
            }

            solutionCard

            ModelCaveat(title: "Limits of this model",
                        text: "Enter GHA and declination from the Nautical Almanac daily page. "
                            + "The built-in ephemeris is compact-series (≈0.1–0.25°), coarser "
                            + "than the almanac, and is not used here.")

            ProvenanceFooter(tool: .sightReduction,
                             evidence: "Bowditch §805's worked sight reproduced exactly.")
        }
    }

    // MARK: The sight form
    //
    // A navigator reads corrections as a ladder, signed, right-aligned, with the
    // two intermediate results ruled off. This is the same data the old
    // "Corrections" section carried, in the shape the work is actually done in.

    private var sightForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CORRECTIONS — THE SIGHT FORM")
                .font(MarineType.section).tracking(1.0)
                .foregroundStyle(theme.palette.inkDim)
                .padding(.horizontal, MarineMetrics.gutter + 8)
            MarineCard {
                VStack(spacing: 0) {
                    formRow("Hs", model.dms(model.hs))
                    formRow("Index correction", model.indexCorrectionSigned,
                            tint: model.indexOffTheArc ? theme.palette.flood : theme.palette.ebb)
                    formRow("Dip (\(model.format(model.heightOfEyeFeet, 0)) ft)",
                            "−\(model.format(model.dip, 1))′",
                            tint: theme.palette.ebb, rule: true)
                    formRow("Apparent altitude ha", model.dms(model.apparentAltitude),
                            bold: true, identifier: "result.ha")
                    formRow("Refraction", "−\(model.format(model.refraction, 1))′",
                            tint: theme.palette.ebb, rule: true, identifier: "result.refraction")
                    HStack {
                        Text("Observed altitude Ho")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.palette.ink)
                        Spacer()
                        Text(model.dms(model.observedAltitude))
                            .font(.system(size: 24, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(theme.palette.water)
                            .accessibilityIdentifier("result.ho")
                    }
                    .padding(.top, 9)
                }
                .padding(.horizontal, MarineMetrics.cardPadding)
                .padding(.vertical, 12)
            }
        }
        .padding(.bottom, MarineMetrics.sectionGap)
        .overlay(alignment: .topTrailing) {
            Text(model.format(model.dip, 1))
                .accessibilityIdentifier("result.dip")
                .hidden()
        }
    }

    private func formRow(_ label: String, _ value: String,
                         tint: Color? = nil, bold: Bool = false,
                         rule: Bool = false, identifier: String? = nil) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.system(size: 14, weight: bold ? .semibold : .regular))
                    .foregroundStyle(bold ? theme.palette.ink : theme.palette.inkDim)
                Spacer()
                Text(value)
                    .font(.system(size: 17, weight: bold ? .semibold : .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(theme.palette.signByGlyph
                                     ? theme.palette.ink
                                     : (tint ?? theme.palette.ink))
                    .accessibilityIdentifier(identifier ?? "result.form.\(label)")
            }
            .padding(.vertical, bold ? 7 : 5)
            if rule { theme.palette.hairline.frame(height: 1) }
        }
    }

    private var solutionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SOLUTION — MARCQ ST-HILAIRE")
                .font(.system(size: 10, weight: .semibold)).tracking(1.2)
                .foregroundStyle(theme.palette.canvas.opacity(0.62))
            let r = model.reduction
            HStack {
                Text("Hc").font(.system(size: 14))
                    .foregroundStyle(theme.palette.canvas.opacity(0.7))
                Spacer()
                Text(model.dms(r.computedAltitudeHc))
                    .font(.system(size: 19, weight: .semibold, design: .monospaced))
                    .accessibilityIdentifier("result.hc")
            }
            .padding(.top, 11)
            HStack {
                Text("Azimuth Zn").font(.system(size: 14))
                    .foregroundStyle(theme.palette.canvas.opacity(0.7))
                Spacer()
                Text("\(model.format(r.azimuthZn, 1)) °T")
                    .font(.system(size: 19, weight: .semibold, design: .monospaced))
                    .accessibilityIdentifier("result.zn")
            }
            .padding(.top, 9)

            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(model.format(abs(r.interceptNM), 1))
                    .font(.system(size: 44, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                Text("nm").font(.system(size: 17, weight: .medium))
                    .foregroundStyle(theme.palette.canvas.opacity(0.7))
                Spacer()
                Text(r.interceptNM >= 0 ? "TOWARD" : "AWAY")
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(theme.palette.ebb)
            }
            .accessibilityIdentifier("result.intercept")
            .padding(.top, 13)
            .overlay(alignment: .top) {
                theme.palette.canvas.opacity(0.18).frame(height: 1)
            }

            Text("Computed Greater Away — the line of position lies away from the body, "
                 + "measured along Zn from the assumed position.")
                .font(MarineType.caption)
                .foregroundStyle(theme.palette.canvas.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
        .foregroundStyle(theme.palette.canvas)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(theme.palette.ink)
        .clipShape(RoundedRectangle(cornerRadius: MarineMetrics.cardRadius, style: .continuous))
        .padding(.horizontal, MarineMetrics.gutter)
        .padding(.bottom, MarineMetrics.sectionGap)
    }

    /// A bare degrees/minutes entry cell: POSIX-formatted, range-clamped.
    private func degreeField(_ value: Binding<Double>, range: ClosedRange<Double>,
                             suffix: String, fraction: ClosedRange<Int> = 0...0,
                             identifier: String) -> some View {
        HStack(spacing: 3) {
            TextField("", value: value, format: MarineFormat.number(fraction))
                .multilineTextAlignment(.trailing)
                .font(.system(size: 21, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(theme.palette.ink)
                .frame(width: 62)
                .padding(.vertical, 3)
                .overlay(alignment: .bottom) {
                    theme.palette.water.opacity(0.35).frame(height: 1.5)
                }
                #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
                #endif
                .accessibilityIdentifier(identifier)
                .onChange(of: value.wrappedValue) { _, new in
                    if new < range.lowerBound { value.wrappedValue = range.lowerBound }
                    if new > range.upperBound { value.wrappedValue = range.upperBound }
                }
            Text(suffix).font(.system(size: 15)).foregroundStyle(theme.palette.inkDim)
        }
    }
}

#Preview("Sight Reduction — day") {
    NavigationStack { SightReductionToolView() }
        .environment(\.marine, MarineTheme(mode: .day))
}

#Preview("Sight Reduction — night red") {
    NavigationStack { SightReductionToolView() }
        .environment(\.marine, MarineTheme(mode: .nightRed))
}
