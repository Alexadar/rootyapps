import Testing
import Foundation
@testable import SpaceWeatherFeed

/// Tests of what the NOAA Kp feed *means*, not of arithmetic.
///
/// ## Why this file exists
///
/// The app reported Kp 4.0 — a G0/G1 boundary storm — on a day the planet measured 1.0. Every one
/// of the 56 tests then in the suite passed, because all of them validated *classifiers*:
/// `Geomag.gScale(forKp: 4.0)` is genuinely G0, and the seven oracle Kits were faithfully
/// converting a number that was simply the wrong number. Nothing tested the step before —
/// `NOAAService` had zero tests and not one captured payload, so the feed's vocabulary was
/// whatever the comment above the parser claimed it was. It claimed wrong.
///
/// So: real bytes, and assertions about which rows are measurements.
@Suite("NOAA Kp feed semantics")
struct NOAAKpFeedTests {

    /// Captured 2026-08-02T10:35Z, the morning the defect was found — 81 rows: 59 `observed`
    /// (07-26T00:00 → 08-02T06:00), 5 `estimated` (09:00 → 21:00 the same day), 17 `predicted`.
    static let payload: [NOAAService.KpRow] = {
        let url = Bundle.module.url(forResource: "noaa-kp-forecast-2026-08-02",
                                    withExtension: "json")!
        return try! JSONDecoder().decode([NOAAService.KpRow].self, from: Data(contentsOf: url))
    }()

    /// 10:35 UTC — the moment of capture, so "future" means what it meant on the day.
    static let capturedAt = Date(timeIntervalSince1970: 1_785_666_900)

    private var panel: KpPanel { NOAAService.parseKp(Self.payload) }

    @Test("the fixture is the real feed, with all three row kinds")
    func fixtureShape() {
        #expect(Self.payload.count == 81)
        let kinds = Dictionary(grouping: Self.payload, by: { $0.observed ?? "?" }).mapValues(\.count)
        #expect(kinds == ["observed": 59, "estimated": 5, "predicted": 17])
    }

    /// The bug, stated directly. NOAA's `estimated` rows are its same-day forecast: they ran
    /// 09:00→21:00 while capture was at 10:35, and read 4.33/4.67/5.67/3.33/4.00 against GFZ's
    /// measured 0.333 for the 09:00 bin. Only `observed` may ever be flagged as measurement.
    @Test("only `observed` rows count as measurement")
    func onlyObservedIsMeasured() {
        for (row, sample) in zip(Self.payload, panel.series) {
            #expect(sample.predicted == (row.observed != "observed"),
                    "row \(row.time_tag) labelled \(row.observed ?? "nil") was misclassified")
        }
        #expect(panel.series.filter { !$0.predicted }.count == 59)
    }

    /// The user-visible symptom: the headline number. Before the fix this was 4.0, taken from a
    /// 21:00 row at 10:35 in the morning.
    @Test("current Kp is the last measured value, not a same-day forecast")
    func currentIsMeasured() throws {
        let now = try #require(panel.nowSample(asOf: Self.capturedAt))
        #expect(now.kp == 1.0)
        #expect(now.time == DateFmt.parseUTC("2026-08-02T06:00:00"))
        #expect(panel.series.last?.kp != now.kp, "must not simply be reading the last row")
    }

    /// `peak24h` gained an upper bound with this fix. It previously anchored its window to a
    /// future row and reported 5.67 — a forecast — as a peak that had occurred.
    @Test("24 h peak covers only measured rows that already happened")
    func peakIsMeasured() throws {
        let peak = try #require(panel.peak24h(asOf: Self.capturedAt))
        #expect(peak == 1.33)
        #expect(peak < 4.33, "5.67 here means a forecast row leaked back into the window")
    }

    /// `observedAt` drives the staleness badge, so it must be the measurement's time. Pointing it
    /// at a forecast row would have the app claim freshness it does not have.
    @Test("observedAt is the newest measurement")
    func observedAtIsMeasurement() {
        #expect(panel.observedAt == DateFmt.parseUTC("2026-08-02T06:00:00"))
    }

    /// Feed-agnostic: whatever the source says, sweeping the clock across the whole series must
    /// never yield a sample that is a forecast or that has not happened yet.
    @Test("current sample is never a forecast and never future-dated",
          arguments: [-36.0, -12.0, -3.0, 0.0, 3.0, 12.0])
    func invariantAcrossTime(offsetHours: Double) {
        let t = Self.capturedAt.addingTimeInterval(offsetHours * 3600)
        guard let s = panel.nowSample(asOf: t) else { return }
        #expect(!s.predicted)
        #expect(s.time <= t)
    }

    /// The regression guard, and the only test here that does not depend on my having read NOAA's
    /// vocabulary correctly: hand a panel a future row wrongly flagged as measurement — exactly
    /// what the parser used to produce — and the clock bound must still reject it. This fails
    /// against the old `KpPanel` even with the parser fixed.
    @Test("a mislabelled future row still cannot become `now`")
    func futureRowRejected() throws {
        let t0 = Date(timeIntervalSince1970: 1_785_666_900)
        let p = KpPanel(series: [
            KpSample(time: t0.addingTimeInterval(-4 * 3600), kp: 1.0, predicted: false),
            KpSample(time: t0.addingTimeInterval(11 * 3600), kp: 4.0, predicted: false),
        ], observedAt: nil)
        #expect(p.nowSample(asOf: t0)?.kp == 1.0)
        #expect(p.peak24h(asOf: t0) == 1.0)

        // `now` reads the ambient clock, which is the path production takes — so build this one
        // relative to `Date()`. Pinning it to a fixed instant would make the assertion expire the
        // moment real time passed the "future" row.
        let real = Date()
        let live = KpPanel(series: [
            KpSample(time: real.addingTimeInterval(-4 * 3600), kp: 1.0, predicted: false),
            KpSample(time: real.addingTimeInterval(11 * 3600), kp: 4.0, predicted: false),
        ], observedAt: nil)
        #expect(live.now == 1.0)
    }

    /// With no measurement there is no current value. Falling back to the first row would show a
    /// forecast under "now" — the same defect, reached by a different path.
    @Test("a forecast-only series has no current value")
    func forecastOnlyHasNoNow() {
        let t0 = Date(timeIntervalSince1970: 1_785_666_900)
        let p = KpPanel(series: [KpSample(time: t0, kp: 7.0, predicted: true)], observedAt: nil)
        #expect(p.nowSample(asOf: t0) == nil)
        #expect(p.peak24h(asOf: t0) == nil)
    }
}
