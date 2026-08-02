import Testing
import Foundation
@testable import SpaceWeatherFeed
import FlareKit

/// ORACLE = NOAA SWPC Space Weather Scales for the alert thresholds:
///  • Geomagnetic storm alerts key off the NOAA G level (G1=Kp5 … G5=Kp9) — an alert
///    is warranted at storm onset (crossing the user's G threshold) and escalation,
///    never for an unchanged level. Source: NOAA SWPC "NOAA Space Weather Scales".
///  • Flare alerts key off the R (radio blackout) scale: R1 begins at class M1
///    (10⁻⁵ W/m²), so "M-class and up" == rScale ≥ 1. Same source.
///  • Aurora alerts use the OVATION max probability; the once-per-UT-day rule is a
///    product decision (no-false-alarm ethos), not a NOAA definition.
@Suite("SpaceWeatherFeed — alert engine + snapshot persistence")
struct SpaceWeatherFeedTests {

    // MARK: helpers

    static let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    static func snapshot(g: Int = 0, kpNow: Double = 2.0,
                         flareClass: String? = nil, flareMax: Date? = nil,
                         auroraPct: Int? = nil) -> SpaceWeatherSnapshot {
        var s = SpaceWeatherSnapshot()
        s.scales = ScalesPanel(g: g, r: 0, s: 0, observedAt: t0)
        s.kp = KpPanel(series: [KpSample(time: t0, kp: kpNow, predicted: false)], observedAt: t0)
        if let flareClass {
            s.flare = FlarePanel(fluxSeries: [],
                                 latestFlare: FlareEvent(maxClass: flareClass, maxTime: flareMax, beginTime: nil),
                                 observedAt: t0)
        }
        if let auroraPct {
            s.aurora = AuroraPanel(maxProbability: auroraPct, kp: kpNow, observedAt: t0)
        }
        return s
    }

    static let on = AlertPrefs(enabled: true)

    // MARK: master switch

    @Test func disabledPrefsFireNothingEvenInAStorm() {
        let storm = Self.snapshot(g: 4, kpNow: 8.0, flareClass: "X2.0", flareMax: Self.t0, auroraPct: 90)
        let out = SpaceAlerts.evaluate(current: storm, prefs: AlertPrefs(), state: .init(), now: Self.t0)
        #expect(out.alerts.isEmpty)
        #expect(out.state == AlertDedupeState())
    }

    // MARK: storms

    @Test func stormFiresOnOnsetOnceAndRearmsWhenCalm() {
        var state = AlertDedupeState()

        // Onset G2: fires.
        var out = SpaceAlerts.evaluate(current: Self.snapshot(g: 2, kpNow: 6.3), prefs: Self.on, state: state, now: Self.t0)
        #expect(out.alerts.map(\.kind) == [.storm])
        #expect(out.alerts[0].detail == .storm(g: 2, kp: 6.3))
        state = out.state

        // Same G2 an hour later: silent.
        out = SpaceAlerts.evaluate(current: Self.snapshot(g: 2, kpNow: 6.0), prefs: Self.on, state: state, now: Self.t0 + 3600)
        #expect(out.alerts.isEmpty)
        state = out.state

        // Escalation to G4: fires again.
        out = SpaceAlerts.evaluate(current: Self.snapshot(g: 4, kpNow: 8.7), prefs: Self.on, state: state, now: Self.t0 + 7200)
        #expect(out.alerts.map(\.kind) == [.storm])
        state = out.state

        // De-escalation to G3 (still ≥ threshold): silent, no downgrade spam.
        out = SpaceAlerts.evaluate(current: Self.snapshot(g: 3), prefs: Self.on, state: state, now: Self.t0 + 10_000)
        #expect(out.alerts.isEmpty)
        state = out.state

        // Calm (G0) re-arms; the next G1 storm fires.
        out = SpaceAlerts.evaluate(current: Self.snapshot(g: 0), prefs: Self.on, state: state, now: Self.t0 + 20_000)
        #expect(out.alerts.isEmpty)
        #expect(out.state.lastStormG == 0)
        out = SpaceAlerts.evaluate(current: Self.snapshot(g: 1, kpNow: 5.0), prefs: Self.on, state: out.state, now: Self.t0 + 30_000)
        #expect(out.alerts.map(\.kind) == [.storm])
    }

    @Test func stormRealertsOnASecondPeak() {
        var state = AlertDedupeState()
        var out = SpaceAlerts.evaluate(current: Self.snapshot(g: 4, kpNow: 8.0), prefs: Self.on, state: state, now: Self.t0)
        #expect(out.alerts.map(\.kind) == [.storm])
        state = out.state

        // Decays to G2 — silent, but the episode's ceiling comes down with it.
        out = SpaceAlerts.evaluate(current: Self.snapshot(g: 2), prefs: Self.on, state: state, now: Self.t0 + 10_800)
        #expect(out.alerts.isEmpty)
        state = out.state

        // Re-intensifies to G4: a genuine second peak, so it alerts again.
        out = SpaceAlerts.evaluate(current: Self.snapshot(g: 4, kpNow: 8.3), prefs: Self.on, state: state, now: Self.t0 + 21_600)
        #expect(out.alerts.map(\.kind) == [.storm])
    }

    @Test func stormBelowUserThresholdStaysSilent() {
        var prefs = Self.on
        prefs.stormThreshold = 3
        let out = SpaceAlerts.evaluate(current: Self.snapshot(g: 2, kpNow: 6.0), prefs: prefs, state: .init(), now: Self.t0)
        #expect(out.alerts.isEmpty)
    }

    // MARK: flares

    @Test func flareFiresAtM1PlusOncePerEvent() {
        var state = AlertDedupeState()

        // C-class: below R1, silent (oracle: R1 begins at M1).
        var out = SpaceAlerts.evaluate(current: Self.snapshot(flareClass: "C5.4", flareMax: Self.t0), prefs: Self.on, state: state, now: Self.t0)
        #expect(out.alerts.isEmpty)

        // M4.2: fires with the Kit's meaning line.
        out = SpaceAlerts.evaluate(current: Self.snapshot(flareClass: "M4.2", flareMax: Self.t0), prefs: Self.on, state: state, now: Self.t0)
        #expect(out.alerts.map(\.kind) == [.flare])
        #expect(out.alerts[0].detail == .flare(maxClass: "M4.2", meaning: Flare.meaning(forClass: "M4.2")))
        state = out.state

        // Same event re-seen: silent.
        out = SpaceAlerts.evaluate(current: Self.snapshot(flareClass: "M4.2", flareMax: Self.t0), prefs: Self.on, state: state, now: Self.t0 + 600)
        #expect(out.alerts.isEmpty)

        // New X event (different max_time): fires.
        out = SpaceAlerts.evaluate(current: Self.snapshot(flareClass: "X1.1", flareMax: Self.t0 + 5000), prefs: Self.on, state: state, now: Self.t0 + 6000)
        #expect(out.alerts.map(\.kind) == [.flare])
    }

    // MARK: aurora

    @Test func auroraFiresAtThresholdOncePerUTDay() {
        var state = AlertDedupeState()

        // 45% < default 50%: silent.
        var out = SpaceAlerts.evaluate(current: Self.snapshot(auroraPct: 45), prefs: Self.on, state: state, now: Self.t0)
        #expect(out.alerts.isEmpty)

        // 65%: fires.
        out = SpaceAlerts.evaluate(current: Self.snapshot(auroraPct: 65), prefs: Self.on, state: state, now: Self.t0)
        #expect(out.alerts.map(\.kind) == [.aurora])
        #expect(out.alerts[0].detail == .aurora(probability: 65, kp: 2.0))
        state = out.state

        // Later the same UT day, still high: silent.
        out = SpaceAlerts.evaluate(current: Self.snapshot(auroraPct: 80), prefs: Self.on, state: state, now: Self.t0 + 3600)
        #expect(out.alerts.isEmpty)
        state = out.state

        // Next UT day: fires again.
        out = SpaceAlerts.evaluate(current: Self.snapshot(auroraPct: 70), prefs: Self.on, state: state, now: Self.t0 + 86_400)
        #expect(out.alerts.map(\.kind) == [.aurora])
    }

    // MARK: snapshot persistence

    @Test func snapshotRoundTripsThroughSharedStore() {
        let suite = "feed-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SharedStore(defaults: defaults)

        var s = Self.snapshot(g: 1, kpNow: 5.3, flareClass: "M1.0", flareMax: Self.t0, auroraPct: 45)
        s.wind = SolarWindPanel(speed: 620, density: 4.2, bt: 12.0, bz: -8.5, observedAt: Self.t0)
        s.solar = SolarPanel(sunspotNumber: 142, f107: 180.5, regionCount: 9, observedAt: Self.t0)
        s.hpo = HpoPanel(readings: [.init(time: Self.t0, value: 5.667)], observedAt: Self.t0)

        #expect(store.load() == nil)
        store.save(s, at: Self.t0)
        let loaded = store.load()
        #expect(loaded?.snapshot == s)
        #expect(loaded?.at == Self.t0)
    }

    @Test func alertPrefsAndStateRoundTripThroughSharedStore() {
        let suite = "feed-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SharedStore(defaults: defaults)

        // Defaults: master off, categories on, G1 / 50% thresholds.
        #expect(store.alertPrefs == AlertPrefs())

        var prefs = AlertPrefs(enabled: true)
        prefs.stormThreshold = 2
        prefs.aurora = false
        store.alertPrefs = prefs
        #expect(store.alertPrefs == prefs)

        var state = AlertDedupeState()
        state.lastStormG = 3
        state.lastFlareMaxTime = Self.t0
        store.alertState = state
        #expect(store.alertState == state)
    }
}
