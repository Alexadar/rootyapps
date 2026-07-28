import SwiftUI
import CoreLocation
import GeomagKit

// ─────────────────────────────────────────────────────────────────────────────
// F5 · DECLINATION
//
// Magnetic variation at the current position from WMM2025, plus true↔magnetic
// conversion. Requires a position; degrades to the last-known one, and then to a
// plain statement, rather than to an error.
//
// ZERO math: `WMM.field` returns the field. `magneticHeading` applies the
// published rule (magnetic = true − variation east) and `decimalYear` is a
// calendar conversion — both carry over from the phone view model unchanged, and
// are the two pre-existing exceptions, not new ones.
//
// ⚠ The crown edits the heading here rather than a keypad: entering 245° on a
// 41 mm screen with a numeric field is a joke. The crown is detented to 1°, and
// clamped to 0…360 — the Kits guard illegal domains with `precondition`, so the
// UI must never be able to hand them an out-of-range value.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class WatchDeclinationViewModel: ObservableObject {
    @Published var trueHeading: Double = 0

    private static let model = WMM(cof: WMM2025.cof)

    func field(at coord: CLLocationCoordinate2D, altitudeKm: Double = 0) -> GeomagField? {
        Self.model?.field(decimalYear: Self.decimalYear(Date()),
                          altitudeKm: altitudeKm,
                          latDeg: coord.latitude,
                          lonDeg: coord.longitude)
    }

    /// Variation applied: magnetic = true − variation east.
    func magneticHeading(_ declinationDeg: Double) -> Double {
        let m = (trueHeading - declinationDeg).truncatingRemainder(dividingBy: 360)
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

    func value(_ v: Double, _ digits: Int = 2) -> String {
        v.formatted(WatchFormat.number(digits...digits))
    }
}

struct WatchDeclinationView: View {
    @StateObject private var model = WatchDeclinationViewModel()
    @StateObject private var location = WatchLocationProvider()
    @Environment(\.watchTheme) private var theme
    @Environment(\.isLuminanceReduced) private var luminanceReduced
    /// Last position we successfully read, so a lost fix does not blank the
    /// screen. Labelled as stale when used.
    @AppStorage("watch.lastLat") private var lastLat: Double = .nan
    @AppStorage("watch.lastLon") private var lastLon: Double = .nan

    private var coordinate: (coord: CLLocationCoordinate2D, live: Bool)? {
        if case .located(let l) = location.state {
            return (l.coordinate, true)
        }
        if lastLat.isFinite, lastLon.isFinite {
            return (CLLocationCoordinate2D(latitude: lastLat, longitude: lastLon), false)
        }
        return nil
    }

    var body: some View {
        GeometryReader { geo in
            let size = WatchSize.measuring(geo.size.width)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("DECLINATION")
                        .font(WatchType.section).tracking(0.8)
                        .foregroundStyle(theme.palette.inkDim)

                    if let (coord, live) = coordinate, let f = model.field(at: coord) {
                        HStack(alignment: .center, spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(alignment: .firstTextBaseline, spacing: 3) {
                                    Text(model.value(f.declinationDeg))
                                        .font(WatchType.hero(size.hero - 4))
                                        .monospacedDigit()
                                        .foregroundStyle(theme.ambientHero)
                                    // East/West is a LETTER, not a colour, and the
                                    // dial shows which side of true north it is on.
                                    Text(f.declinationDeg >= 0 ? "°E" : "°W")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(theme.palette.inkDim)
                                }
                                Text(f.declinationDeg >= 0 ? "magnetic east of true"
                                                           : "magnetic west of true")
                                    .font(WatchType.caption)
                                    .foregroundStyle(theme.palette.inkDim)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityIdentifier("result.declination")
                            .accessibilityLabel("Variation \(model.value(f.declinationDeg)) degrees "
                                                + (f.declinationDeg >= 0 ? "east" : "west")
                                                + ", magnetic north lies "
                                                + (f.declinationDeg >= 0 ? "east" : "west")
                                                + " of true north.")
                            Spacer(minLength: 2)
                            WatchVariationDial(declinationDeg: f.declinationDeg,
                                               size: size == .compact ? 54 : 64)
                        }

                        if !live {
                            Text("Last known position — no current fix.")
                                .font(WatchType.caption)
                                .foregroundStyle(theme.palette.caution)
                                .accessibilityIdentifier("result.staleFix")
                        }

                        // True → magnetic, driven by the crown.
                        WatchCard {
                            HStack(spacing: 6) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("TRUE").font(.system(size: 9, weight: .semibold))
                                        .tracking(0.8)
                                        .foregroundStyle(theme.palette.inkDim)
                                    Text(String(format: "%03.0f°", model.trueHeading))
                                        .font(WatchType.value)
                                        .monospacedDigit()
                                        .foregroundStyle(theme.ambientInk)
                                }
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(theme.palette.inkDim)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("MAGNETIC").font(.system(size: 9, weight: .semibold))
                                        .tracking(0.8)
                                        .foregroundStyle(theme.palette.inkDim)
                                    Text(String(format: "%05.1f°",
                                                model.magneticHeading(f.declinationDeg)))
                                        .font(WatchType.value)
                                        .monospacedDigit()
                                        .foregroundStyle(theme.palette.water)
                                }
                                Spacer(minLength: 2)
                                Image(systemName: "digitalcrown.horizontal.arrow.clockwise")
                                    .font(.system(size: 12))
                                    .foregroundStyle(theme.palette.inkDim)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityIdentifier("result.magneticHeading")
                            .accessibilityLabel("True \(Int(model.trueHeading)) degrees is "
                                + "magnetic \(model.value(model.magneticHeading(f.declinationDeg), 1)) "
                                + "degrees. Turn the Digital Crown to change the true heading.")
                            .accessibilityAdjustableAction { direction in
                                switch direction {
                                case .increment: model.trueHeading = min(model.trueHeading + 1, 360)
                                case .decrement: model.trueHeading = max(model.trueHeading - 1, 0)
                                default: break
                                }
                            }
                        }
                        .focusable(!luminanceReduced)
                        .digitalCrownRotation($model.trueHeading,
                                              from: 0, through: 360, by: 1,
                                              sensitivity: .low,
                                              isContinuous: true,
                                              isHapticFeedbackEnabled: true)

                        if !luminanceReduced {
                            HStack(spacing: 6) {
                                stat("DIP", model.value(f.inclinationDeg, 1) + "°",
                                     "result.inclination")
                                stat("F", model.value(f.f, 0) + " nT", "result.totalIntensity")
                            }
                            WatchCaveat(text: "Core field only — crustal anomalies, magnetic "
                                            + "storms and vessel deviation are not modelled. "
                                            + "Model valid to 2030.0.")
                            WatchProvenance(kit: "GeomagKit · WMM2025",
                                            authority: "the 100 official WMM2025 test values")
                        }
                    } else {
                        // No position: a statement and a way forward, not an error.
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Position needed")
                                .font(WatchType.label)
                                .foregroundStyle(theme.ambientInk)
                            Text("Variation depends on where you are. Marine Nav reads the "
                                 + "watch's position only while this screen is open, and makes "
                                 + "no network requests.")
                                .font(WatchType.caption)
                                .foregroundStyle(theme.palette.inkDim)
                                .fixedSize(horizontal: false, vertical: true)
                            Button {
                                location.request()
                            } label: {
                                Label("Use my position", systemImage: "location")
                                    .font(WatchType.label)
                                    .frame(maxWidth: .infinity, minHeight: WatchMetrics.target)
                            }
                            .accessibilityIdentifier("input.requestLocation")
                            Text("Or read variation for any coordinate on the iPhone or Mac.")
                                .font(WatchType.caption)
                                .foregroundStyle(theme.palette.inkDim)
                        }
                        .accessibilityIdentifier("result.positionNeeded")
                    }
                }
                .padding(.horizontal, size.gutter)
                .padding(.bottom, 8)
            }
            .background(theme.palette.canvas)
        }
        .environment(\.watchTheme, luminanceReduced ? theme.dimmed : theme)
        .onChange(of: location.state) { _, new in
            if case .located(let l) = new {
                lastLat = l.coordinate.latitude
                lastLon = l.coordinate.longitude
            }
        }
    }

    private func stat(_ title: String, _ value: String, _ identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 9, weight: .semibold)).tracking(0.8)
                .foregroundStyle(theme.palette.inkDim)
            Text(value)
                .font(WatchType.mono13)
                .monospacedDigit()
                .foregroundStyle(theme.ambientInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(theme.ambientHairline, lineWidth: 1))
        .accessibilityIdentifier(identifier)
    }
}

#Preview("Declination — dusk") {
    WatchDeclinationView().environment(\.watchTheme, WatchTheme(mode: .dark))
}
