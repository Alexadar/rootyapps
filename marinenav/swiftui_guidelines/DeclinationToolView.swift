import SwiftUI
import GeomagKit

/// Magnetic declination from WMM2025, on device. ZERO math here beyond applying
/// the variation to a heading, which is the published rule (magnetic = true −
/// variation east) and not a field computation: the field itself comes from
/// `WMM.field`.
@MainActor
final class DeclinationViewModel: ObservableObject {
    @Published var latitude: Double = 37.81
    @Published var longitude: Double = -122.47
    @Published var altitudeKm: Double = 0
    @Published var trueHeading: Double = 0

    private static let model = WMM(cof: WMM2025.cof)

    var field: GeomagField? {
        Self.model?.field(decimalYear: Self.decimalYear(Date()),
                          altitudeKm: altitudeKm,
                          latDeg: latitude, lonDeg: longitude)
    }

    /// Variation applied: magnetic = true − variation east.
    var magneticHeading: Double? {
        guard let d = field?.declinationDeg else { return nil }
        let m = (trueHeading - d).truncatingRemainder(dividingBy: 360)
        return m < 0 ? m + 360 : m
    }

    static func decimalYear(_ date: Date) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let y = cal.component(.year, from: date)
        let start = cal.date(from: DateComponents(year: y, month: 1, day: 1))!
        let next = cal.date(from: DateComponents(year: y + 1, month: 1, day: 1))!
        return Double(y) + date.timeIntervalSince(start) / next.timeIntervalSince(start)
    }

    func format(_ v: Double, _ digits: Int = 2) -> String {
        String(format: "%.\(digits)f", v)
    }
}

struct DeclinationToolView: View {
    @StateObject private var model = DeclinationViewModel()
    @Environment(\.marine) private var theme

    var body: some View {
        ToolScreen(tool: .declination,
                   badges: ["Offline", "WMM2025", "No subscription"]) {
            if let f = model.field {
                declinationHero(f)

                ToolSection(title: "Position") {
                    NumberField(label: "Latitude", value: $model.latitude,
                                range: -90...90, step: 0.1, fraction: 0...4,
                                identifier: "input.latitude")
                    MarineDivider()
                    NumberField(label: "Longitude", value: $model.longitude,
                                range: -180...180, step: 0.1, fraction: 0...4,
                                identifier: "input.longitude")
                    MarineDivider()
                    NumberField(label: "Altitude", value: $model.altitudeKm,
                                range: -1...600, unit: "km", step: 1, fraction: 0...2,
                                identifier: "input.altitude")
                }

                fieldGrid(f)

                ToolSection(title: "Apply the variation") {
                    NumberField(label: "True heading", value: $model.trueHeading,
                                range: 0...360, unit: "°T", step: 1, fraction: 0...1,
                                identifier: "input.trueHeading")
                    MarineDivider()
                    if let m = model.magneticHeading {
                        HStack {
                            Text("Magnetic heading")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(theme.palette.ink)
                            Spacer()
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(model.format(m, 1))
                                    .font(MarineType.result)
                                    .monospacedDigit()
                                    .foregroundStyle(theme.palette.water)
                                Text("°M")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(theme.palette.inkDim)
                            }
                            .accessibilityIdentifier("result.magneticHeading")
                        }
                        .frame(minHeight: MarineMetrics.controlHeight)
                        .padding(.horizontal, MarineMetrics.cardPadding)
                        .background(theme.palette.water.opacity(0.05))
                    }
                    MarineDivider()
                    Text("Variation east, compass least — easterly declination subtracts from a "
                         + "true heading to give magnetic. Deviation from the vessel's own "
                         + "magnetism is not included.")
                        .font(MarineType.caption)
                        .foregroundStyle(theme.palette.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(MarineMetrics.cardPadding)
                }

                ModelCaveat(title: "Limits of this model",
                            text: "Main (core) field only. Local crustal anomalies, magnetic "
                                + "storms and vessel deviation are not modelled.",
                            trailing: "valid to 2030.0")

                ProvenanceFooter(tool: .declination,
                                 evidence: "Within 5 nT and 0.05° of all 100 official WMM2025 "
                                         + "test values.")
            } else {
                Text("Magnetic model failed to load.")
                    .font(MarineType.label)
                    .foregroundStyle(theme.palette.caution)
                    .padding(.horizontal, 18)
            }
        }
    }

    private func declinationHero(_ f: GeomagField) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(model.format(f.declinationDeg))
                        .font(MarineType.heroCompact)
                        .monospacedDigit()
                        .foregroundStyle(theme.palette.heroInk)
                        .accessibilityIdentifier("result.declination")
                    Text(f.declinationDeg >= 0 ? "°E" : "°W")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(theme.palette.water)
                }
                Text("DECLINATION · VARIATION")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(theme.palette.inkDim)
                Text(f.declinationDeg >= 0
                     ? "Magnetic north lies east of true"
                     : "Magnetic north lies west of true")
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.palette.inkDim)
            }
            Spacer(minLength: 8)
            VariationDial(declinationDeg: f.declinationDeg)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }

    private func fieldGrid(_ f: GeomagField) -> some View {
        HStack(spacing: 10) {
            statCard("Dip I", model.format(f.inclinationDeg), "°", "result.inclination")
            statCard("Horiz H", model.format(f.h, 0), "nT", "result.horizontal")
            statCard("Total F", model.format(f.f, 0), "nT", "result.totalIntensity")
        }
        .padding(.horizontal, MarineMetrics.gutter)
        .padding(.bottom, MarineMetrics.sectionGap)
    }

    private func statCard(_ title: String, _ value: String, _ unit: String,
                          _ identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(theme.palette.inkDim)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(theme.palette.ink)
                Text(unit)
                    .font(MarineType.caption)
                    .foregroundStyle(theme.palette.inkDim)
            }
            .accessibilityIdentifier(identifier)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(theme.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(theme.palette.hairline, lineWidth: 1))
    }
}

#Preview("Declination — day") {
    NavigationStack { DeclinationToolView() }
        .environment(\.marine, MarineTheme(mode: .day))
}

#Preview("Declination — night red") {
    NavigationStack { DeclinationToolView() }
        .environment(\.marine, MarineTheme(mode: .nightRed))
}
