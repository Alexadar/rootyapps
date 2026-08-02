import Foundation
import GeomagKit
import HpoKit

public extension SpaceWeatherSnapshot {

    /// A complete, deterministic snapshot for UI tests and gallery previews.
    ///
    /// ## Why this exists
    ///
    /// Every number this app shows comes from a live NOAA or GFZ feed. A UI test that asserts
    /// "Kp 5.3" against real data is asserting today's weather: correct this afternoon, wrong
    /// tomorrow, and flaky whenever a source is slow or down. That is not a test of the app.
    ///
    /// So a UI test seeds this instead (`EARTHAROUND_FIXTURE=1`) and asserts that THESE values reach
    /// the right labels — which is the only thing a UI test can prove that a Kit test cannot: the
    /// wiring. The arithmetic stays where it belongs, in the seven oracle Kits.
    ///
    /// ## Choosing the values
    ///
    /// Every one is picked so the *derived* value is unambiguous and comes from a Kit function, not
    /// from a literal in a test:
    ///
    /// | field | value | derives |
    /// |---|---|---|
    /// | `kp.now` | 5.3 | G1 (`Geomag.gScale` — G1 starts at Kp 5), ap 48, "Minor" |
    /// | `kp` 24 h peak | 6.0 | distinct from `now`, so a test cannot pass by reading the wrong one |
    /// | `flare` latest | M1.0 | R1 (`Flare.rScale` — R1 starts at M1) |
    /// | `flare` 24 h peak | M3.2 | strictly stronger than latest, again distinguishable |
    /// | `wind.bz` | −8.5 | southward, so the coupling flags are ON rather than absent |
    /// | `hpo` latest | 4.667 | below the Kp 9 ceiling, so `exceedsCeiling` is false |
    /// | `solar` | 96 / 142.7 | two different numbers, so a swapped binding is visible |
    ///
    /// Deliberately NOT round numbers where a formatter is involved: 5.3 and 142.7 would render as
    /// "5,3" and "142,7" in a comma-decimal locale, so they also prove the language pin is working.
    static var uiTestFixture: SpaceWeatherSnapshot {
        // A fixed instant, not `Date()`: an observation age of "just now" vs "2 minutes ago" changes
        // the StaleBadge text, and a test that reads it should not be racing the clock. Far enough
        // in the past to be stable, recent enough not to trip the staleness thresholds.
        let now = Date(timeIntervalSince1970: 1_785_000_000)   // 2026-07-25 UTC, fixed
        var s = SpaceWeatherSnapshot()

        // Three measured rows then two forecast rows. The forecast rows are the point: every
        // sample here used to be `predicted: false`, which meant the UI suite could not tell a
        // measurement from a prediction either — the chart's ghosting and the "hide forecast"
        // toggle both had nothing to act on. `kp.now` stays 5.3, the newest MEASURED value, so
        // a forecast row leaking into the headline shows up as 7.0 rather than as a silent pass.
        s.kp = KpPanel(series: [
            KpSample(time: now.addingTimeInterval(-6 * 3600), kp: 6.0, predicted: false),
            KpSample(time: now.addingTimeInterval(-3 * 3600), kp: 4.0, predicted: false),
            KpSample(time: now,                               kp: 5.3, predicted: false),
            KpSample(time: now.addingTimeInterval(3 * 3600),  kp: 7.0, predicted: true),
            KpSample(time: now.addingTimeInterval(6 * 3600),  kp: 6.7, predicted: true),
        ], observedAt: now)

        s.scales = ScalesPanel(g: 1, r: 1, s: 0, observedAt: now)

        s.wind = SolarWindPanel(speed: 620, density: 4.2, bt: 12, bz: -8.5, observedAt: now)

        s.aurora = AuroraPanel(maxProbability: 45, kp: 5.3, observedAt: now)

        s.flare = FlarePanel(
            fluxSeries: [FluxSample(time: now, flux: 1.0e-5)],
            latestFlare: FlareEvent(maxClass: "M1.0", maxTime: now, beginTime: nil),
            recentFlares: [FlareEvent(maxClass: "M1.0", maxTime: now, beginTime: nil),
                           FlareEvent(maxClass: "M3.2", maxTime: now.addingTimeInterval(-9 * 3600),
                                      beginTime: nil)],
            observedAt: now)

        s.solar = SolarPanel(sunspotNumber: 96, f107: 142.7, regionCount: 8, observedAt: now)

        s.hpo = HpoPanel(readings: (0..<8).map {
            Hpo.Reading(time: now.addingTimeInterval(Double($0 - 7) * 1800),
                        value: [3.0, 3.333, 4.0, 4.333, 5.0, 5.333, 4.333, 4.667][$0])
        }, observedAt: now)

        return s
    }
}
