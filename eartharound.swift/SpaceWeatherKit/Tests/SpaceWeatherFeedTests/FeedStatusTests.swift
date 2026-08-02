import Testing
import Foundation
@testable import SpaceWeatherFeed

/// ORACLE = the publishers' own cadences, which is what "stale" has to be judged against:
///  • NOAA SWPC re-issues the scales / GOES X-ray / solar-wind summaries about every minute,
///    and OVATION about every five.
///  • The planetary Kp index is defined on Bartels' three-hour intervals (GFZ/NOAA).
///  • GFZ's Hp30 is a 30-minute index.
///  • F10.7 is issued three times a day (NOAA SWPC daily solar data).
/// A single flat threshold cannot serve all of these: at 2 h it marks F10.7 stale permanently
/// and Hp30 never. Each source is therefore allowed two missed publications before it counts
/// as stale.
@Suite("Feed status — per-source freshness, merge, and the widget clobber")
struct FeedStatusTests {

    static let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    @Test func staleIsJudgedAgainstEachSourcesOwnCadence() {
        var s = FeedStatus()
        for source in FeedSource.allCases { s.record(source, .ok, at: Self.t0) }

        // Two hours on: the minute-cadence feeds are long stale, Kp and F10.7 are not —
        // the exact case the old flat 2h rule got backwards.
        let twoHoursLater = Self.t0.addingTimeInterval(2 * 3600)
        #expect(s.isStale(.scales, now: twoHoursLater))
        #expect(s.isStale(.aurora, now: twoHoursLater))
        #expect(s.isStale(.hpo, now: twoHoursLater))
        #expect(!s.isStale(.kp, now: twoHoursLater))
        #expect(!s.isStale(.solar, now: twoHoursLater))

        // A day on, everything is stale.
        let dayLater = Self.t0.addingTimeInterval(24 * 3600)
        #expect(FeedSource.allCases.allSatisfy { s.isStale($0, now: dayLater) })
    }

    @Test func neverSucceededCountsAsStale() {
        let s = FeedStatus()
        #expect(FeedSource.allCases.allSatisfy { s.isStale($0, now: Self.t0) })
    }

    @Test func failureIsDistinctFromASlowPublisher() {
        var s = FeedStatus()
        s.record(.kp, .ok, at: Self.t0)             // fetched fine; source is just 3-hourly
        s.record(.hpo, .failed, at: Self.t0)        // our fetch died
        s.record(.solar, .empty, at: Self.t0)       // 200 that decoded to nothing
        s.record(.wind, .skippedCellular, at: Self.t0)

        #expect(!s.didFail(.kp))
        #expect(s.didFail(.hpo))
        #expect(s.didFail(.solar))                  // empty must not read as success
        #expect(s.didFail(.wind))
        #expect(s.anyFailed)
        #expect(!s.allFailed)

        // A failed attempt must not advance lastSuccess.
        #expect(s[.hpo].lastSuccess == nil)
        #expect(s[.hpo].lastAttempt == Self.t0)
        #expect(s[.kp].lastSuccess == Self.t0)
    }

    @Test func mergeKeepsTheFresherSuccessPerSource() {
        var mine = FeedStatus()
        mine.record(.hpo, .ok, at: Self.t0.addingTimeInterval(600))   // app fetched Hp30 recently
        mine.record(.kp, .ok, at: Self.t0)

        var theirs = FeedStatus()                                      // widget: 5 sources, no hpo
        theirs.record(.kp, .ok, at: Self.t0.addingTimeInterval(900))
        theirs.record(.scales, .ok, at: Self.t0.addingTimeInterval(900))

        mine.merge(theirs)
        #expect(mine[.kp].lastSuccess == Self.t0.addingTimeInterval(900))    // newer wins
        #expect(mine[.hpo].lastSuccess == Self.t0.addingTimeInterval(600))   // untouched
        #expect(mine[.scales].lastSuccess == Self.t0.addingTimeInterval(900))
    }

    /// The reported bug: the widget fetches five of seven sources but used to save the WHOLE
    /// snapshot, rewriting Hp30 and Solar at their stale cached values under a fresh timestamp.
    @Test func aPartialFetchCannotRegressPanelsItDidNotFetch() {
        let suite = "feed-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SharedStore(defaults: defaults)

        // The app has just fetched all seven, including a good Hp30 chart.
        var full = SpaceWeatherSnapshot()
        full.hpo = HpoPanel(readings: [.init(time: Self.t0, value: 4.0)], observedAt: Self.t0)
        full.kp = KpPanel(series: [KpSample(time: Self.t0, kp: 2.0, predicted: false)], observedAt: Self.t0)
        var fullStatus = FeedStatus()
        for source in FeedSource.allCases { fullStatus.record(source, .ok, at: Self.t0) }
        store.merge(full, status: fullStatus, at: Self.t0)

        // Now the widget reports back later having fetched only Kp — with NO hpo.
        var partial = SpaceWeatherSnapshot()
        partial.kp = KpPanel(series: [KpSample(time: Self.t0, kp: 5.0, predicted: false)], observedAt: Self.t0)
        var partialStatus = FeedStatus()
        partialStatus.record(.kp, .ok, at: Self.t0.addingTimeInterval(300))
        store.merge(partial, status: partialStatus, at: Self.t0.addingTimeInterval(300))

        let after = store.load()?.snapshot
        #expect(after?.kp?.now == 5.0)                       // the source it did fetch advanced
        #expect(after?.hpo?.readings.count == 1)             // the one it didn't is intact
        #expect(store.status[.hpo].lastSuccess == Self.t0)   // and still reports its own age
    }

    @Test func cellularIsAllowedUnlessTurnedOff() {
        let suite = "feed-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SharedStore(defaults: defaults)

        #expect(store.cellularAllowed)          // default ON, as asked
        store.cellularAllowed = false
        #expect(!store.cellularAllowed)
    }

    /// This test used to assert the opposite — that NOAA's `estimated` rows were a nowcast worth
    /// showing as current — and it passed, because it was handed a `predicted: false` flag rather
    /// than deriving one from a payload. It encoded the bug as the requirement. Measurement won:
    /// see `NOAAKpFeedTests`.
    @Test func kpHeadlineIsMeasuredNotForecast() {
        let series = [
            KpSample(time: Self.t0, kp: 2.0, predicted: false),
            KpSample(time: Self.t0.addingTimeInterval(3 * 3600), kp: 5.0, predicted: true),
            KpSample(time: Self.t0.addingTimeInterval(6 * 3600), kp: 7.0, predicted: true),
        ]
        let panel = KpPanel(series: series, observedAt: Self.t0)
        #expect(panel.now == 2.0)   // the measurement, not the 5.0 same-day forecast or the 7.0
    }
}
