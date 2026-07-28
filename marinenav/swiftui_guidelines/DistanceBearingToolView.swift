import SwiftUI
import GeodesyKit

/// Great-circle passage on WGS-84. ZERO math here: `Vincenty.inverse` and
/// `Vincenty.direct` do the work; `nm(_:)` is the published nautical-mile
/// definition, not a computation.
@MainActor
final class DistanceBearingViewModel: ObservableObject {
    @Published var lat1: Double = 37.81
    @Published var lon1: Double = -122.47
    @Published var lat2: Double = 21.31
    @Published var lon2: Double = -157.86

    // Departure leg, for the direct problem.
    @Published var courseDeg: Double = 240
    @Published var distanceNM: Double = 500

    var inverse: Vincenty.Inverse {
        Vincenty.inverse(lat1: lat1, lon1: lon1, lat2: lat2, lon2: lon2)
    }

    var direct: Vincenty.Direct {
        Vincenty.direct(lat1: lat1, lon1: lon1,
                        azimuth1Deg: courseDeg, distanceM: distanceNM * 1852.0)
    }

    static let metresPerNauticalMile = 1852.0

    func nm(_ metres: Double) -> Double { metres / Self.metresPerNauticalMile }

    func format(_ v: Double, _ digits: Int = 2) -> String {
        v.isFinite ? String(format: "%.\(digits)f", v) : "—"
    }

    /// "37.8100°N" — presentation only.
    func latText(_ v: Double) -> String {
        String(format: "%.4f°%@", abs(v), v >= 0 ? "N" : "S")
    }

    func lonText(_ v: Double) -> String {
        String(format: "%.4f°%@", abs(v), v >= 0 ? "E" : "W")
    }
}

struct DistanceBearingToolView: View {
    @StateObject private var model = DistanceBearingViewModel()
    @Environment(\.marine) private var theme

    var body: some View {
        ToolScreen(tool: .distanceBearing,
                   badges: ["Offline", "WGS-84", "No subscription"]) {
            ToolSection(title: "From") {
                NumberField(label: "Latitude", value: $model.lat1, range: -90...90,
                            step: 0.1, fraction: 0...4, identifier: "input.fromLat")
                MarineDivider()
                NumberField(label: "Longitude", value: $model.lon1, range: -180...180,
                            step: 0.1, fraction: 0...4, identifier: "input.fromLon")
            }

            ToolSection(title: "To") {
                NumberField(label: "Latitude", value: $model.lat2, range: -90...90,
                            step: 0.1, fraction: 0...4, identifier: "input.toLat")
                MarineDivider()
                NumberField(label: "Longitude", value: $model.lon2, range: -180...180,
                            step: 0.1, fraction: 0...4, identifier: "input.toLon")
            }

            let r = model.inverse
            if r.converged {
                passageHero(r)
                courseCards(r)
            } else {
                ModelCaveat(title: "Non-convergent",
                            text: "Vincenty's inverse solution does not converge for "
                                + "near-antipodal points. Reported rather than guessed.")
                    .accessibilityIdentifier("result.nonConvergent")
            }

            ToolSection(title: "Run a course — direct problem") {
                NumberField(label: "Course", value: $model.courseDeg, range: 0...360,
                            unit: "°T", step: 1, fraction: 0...1, identifier: "input.course")
                MarineDivider()
                NumberField(label: "Distance", value: $model.distanceNM, range: 0...12000,
                            unit: "nm", step: 10, fraction: 0...1,
                            identifier: "input.runDistance")
                MarineDivider()
                let d = model.direct
                if d.converged {
                    HStack {
                        Text("Arrival")
                            .font(MarineType.label)
                            .foregroundStyle(theme.palette.inkDim)
                        Spacer()
                        HStack(spacing: 8) {
                            Text(model.latText(d.lat2Deg))
                                .accessibilityIdentifier("result.arrivalLat")
                            Text(model.lonText(d.lon2Deg))
                                .accessibilityIdentifier("result.arrivalLon")
                        }
                        .font(.system(size: 19, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(theme.palette.water)
                    }
                    .frame(minHeight: MarineMetrics.controlHeight)
                    .padding(.horizontal, MarineMetrics.cardPadding)
                    .background(theme.palette.water.opacity(0.05))
                    MarineDivider()
                    ResultRow(label: "Course on arrival",
                              value: model.format(d.azimuth2Deg, 1), unit: "°T",
                              identifier: "result.arrivalCourse")
                }
            }

            ModelCaveat(title: "Limits of this model",
                        text: "Geodesic (shortest path) on the WGS-84 ellipsoid — not a rhumb "
                            + "line, and it takes no view on whether the track crosses land. "
                            + "Near-antipodal pairs are reported as non-convergent rather than "
                            + "guessed.")

            ProvenanceFooter(tool: .distanceBearing,
                             evidence: "Direct and inverse invert each other to 1e-8°.")
        }
    }

    private func passageHero(_ r: Vincenty.Inverse) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(model.format(model.nm(r.distanceM), 1))
                    .font(MarineType.heroCompact)
                    .monospacedDigit()
                    .foregroundStyle(theme.palette.heroInk)
                    .accessibilityIdentifier("result.distanceNM")
                Text("nm")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(theme.palette.inkDim)
            }
            HStack(spacing: 6) {
                Text(model.format(r.distanceM / 1000, 1))
                    .accessibilityIdentifier("result.distanceKM")
                Text("km · geodesic, WGS-84")
            }
            .font(.system(size: 15, design: .monospaced))
            .foregroundStyle(theme.palette.inkDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }

    private func courseCards(_ r: Vincenty.Inverse) -> some View {
        HStack(spacing: 10) {
            courseCard("Initial course", model.format(r.azimuth1Deg, 1),
                       accent: true, identifier: "result.initialCourse")
            courseCard("Final course", model.format(r.azimuth2Deg, 1),
                       accent: false, identifier: "result.finalCourse")
        }
        .padding(.horizontal, MarineMetrics.gutter)
        .padding(.bottom, MarineMetrics.sectionGap)
    }

    private func courseCard(_ title: String, _ value: String,
                            accent: Bool, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(theme.palette.inkDim)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(accent ? theme.palette.water : theme.palette.ink)
                Text("°T")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.palette.inkDim)
            }
            .accessibilityIdentifier(identifier)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(theme.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: MarineMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: MarineMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.palette.hairline, lineWidth: 1))
    }
}

#Preview("Distance & Bearing — day") {
    NavigationStack { DistanceBearingToolView() }
        .environment(\.marine, MarineTheme(mode: .day))
}

#Preview("Distance & Bearing — dark") {
    NavigationStack { DistanceBearingToolView() }
        .environment(\.marine, MarineTheme(mode: .dark))
}
