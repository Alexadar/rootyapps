import SwiftUI
import EphemerisKit

/// Scaffolding for the watch app — deliberately the "Now" screen, not the wheel.
///
/// The wheel is the intended hero (Digital Crown scrubs time, planets sweep the ring), but whether
/// a stripped wheel is legible at 41mm is unverified, and a design brief cannot answer it — a
/// mockup will always look sharper than a real render at real pixel density. So this starts with
/// the screen that is certain to work, and the wheel is added only after the 41mm probe.
///
/// Everything shown is computed on-device by EphemerisKit. Nothing is fetched, and nothing is
/// synced from the phone except preferences: app groups do not cross devices, so place and
/// language arrive over WatchConnectivity, while positions are simply recomputed here.
struct WatchRootView: View {
    @State private var now = Date.now

    /// Same construction the phone uses — there is no `Ephemeris.positions(at:)`; the Kit exposes
    /// longitude and daily motion per body and the caller assembles them.
    private var positions: [BodyPosition] {
        CelestialBody.allCases.map {
            BodyPosition(body: $0,
                         longitude: Ephemeris.longitude(of: $0, at: now),
                         speed: Ephemeris.dailyMotion(of: $0, at: now))
        }
    }
    private var location: GeoLocation? { SharedStore().location }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let location, let houses = Houses.compute(at: now, location: location,
                                                                 system: SharedStore().houseSystem) {
                        row("AC", ZodiacSign.from(longitude: houses.angles.ascendant).glyph,
                            degMin(houses.angles.ascendant))
                        row("MC", ZodiacSign.from(longitude: houses.angles.midheaven).glyph,
                            degMin(houses.angles.midheaven))
                    } else {
                        // The Ascendant needs an observer; the planets do not. Degrade to what is
                        // still true rather than showing an error for the whole screen.
                        Text(verbatim: "Set a place in Ephemeris to see the Ascendant")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } header: { Text(verbatim: "ANGLES") }

                Section {
                    ForEach(positions) { p in
                        row(p.body.name, p.body.glyph, p.degMinString, retrograde: p.retrograde)
                    }
                } header: { Text(verbatim: "POSITIONS") }
            }
            .navigationTitle("Ephemeris")
        }
    }

    private func row(_ label: String, _ glyph: String, _ value: String,
                     retrograde: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: glyph)
            Text(verbatim: label).font(.caption2).foregroundStyle(.secondary)
            Spacer()
            if retrograde { Text(verbatim: "℞").foregroundStyle(.orange) }
            Text(verbatim: value).font(.caption).monospacedDigit()
        }
    }

    private func degMin(_ longitude: Double) -> String {
        let within = AstroMath.norm360(longitude).truncatingRemainder(dividingBy: 30)
        let d = Int(within), m = Int((within - Double(d)) * 60)
        return String(format: "%d° %02d′", d, m)
    }
}
