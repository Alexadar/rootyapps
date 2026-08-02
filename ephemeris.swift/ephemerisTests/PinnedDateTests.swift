import Testing
import Foundation
import EphemerisKit
@testable import Ephemeris

/// Proves the pinned-instant override actually reaches the view model.
///
/// Written because four UI tests failed showing a Sun position ~23 days away from the pinned date,
/// which has two very different causes — the override not being honoured in code, or the variable
/// not reaching the app process on a simulator. This isolates the first, in milliseconds, without
/// booting anything.
@Suite("Pinned instant")
struct PinnedDateTests {

    @Test func launchOverrideParsesTheInstant() {
        setenv("EPHEMERIS_DATE", "2026-07-15T12:00:00Z", 1)
        defer { unsetenv("EPHEMERIS_DATE") }

        let parsed = LaunchOverride.pinnedDate()
        #expect(parsed != nil, "ISO-8601 with a Z suffix must parse")
        #expect(parsed?.timeIntervalSince1970 == 1784116800)
    }

    @MainActor
    @Test func viewModelStartsAtThePinnedInstant() {
        setenv("EPHEMERIS_DATE", "2026-07-15T12:00:00Z", 1)
        defer { unsetenv("EPHEMERIS_DATE") }

        let vm = ChartViewModel()
        #expect(vm.date.timeIntervalSince1970 == 1784116800,
                "ChartViewModel must open on the pinned instant, not the wall clock")
    }

    /// The number the failing UI test actually read. If this matches the Kit while the UI shows
    /// something else, the defect is in delivery or in the view — not in the ephemeris.
    @Test func sunAtThePinnedInstantIsWhereTheKitSaysItIs() {
        let date = ISO8601DateFormatter().date(from: "2026-07-15T12:00:00Z")!
        let sun = BodyPosition(body: .sun,
                               longitude: Ephemeris.longitude(of: .sun, at: date),
                               speed: Ephemeris.dailyMotion(of: .sun, at: date))
        #expect(sun.degMinString == "23° 02′")
        #expect(sun.sign == .cancer)
    }

    /// An unset or malformed value must fall back to the live clock rather than to some fixed date —
    /// a silently wrong constant would be worse than no override at all.
    @Test func malformedValueFallsBackToNow() {
        setenv("EPHEMERIS_DATE", "not-a-date", 1)
        defer { unsetenv("EPHEMERIS_DATE") }
        #expect(LaunchOverride.pinnedDate() == nil)
    }
}
