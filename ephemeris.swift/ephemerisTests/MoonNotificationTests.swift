import Testing
import Foundation
import EphemerisKit
@testable import Ephemeris

/// The moon-alert scheduler, tested without a notification centre.
///
/// Everything asserted here is the pure half — which instants get scheduled and what components
/// describe them. That split exists so these can run at all: `UNUserNotificationCenter` needs a
/// real app, a granted permission and a device willing to wait days for a trigger to fire.
///
/// The load-bearing case is the time zone. A full moon is an **absolute instant**, but a calendar
/// trigger fires at a *wall-clock* time — so components taken in local time land an hour off across
/// a daylight-saving boundary, and are correct the rest of the year. That is the same shape as the
/// `RiseSet` defect: invisible under the UTC-only testing that was standard here.
@Suite("Moon notifications")
struct MoonNotificationTests {

    private func utcDate(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = h
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.date(from: c)!
    }

    // MARK: - What gets scheduled

    @Test func scheduleReturnsTheRequestedCountOfFullAndNewMoonsInOrder() {
        let now = utcDate(2026, 3, 1)
        let s = MoonNotifications.schedule(from: now, limit: 12)

        #expect(s.count == 12, "asked for 12, got \(s.count)")
        for (event, _) in s {
            #expect(event.phase == .full || event.phase == .new,
                    "quarters must not be scheduled; got \(event.phase.rawValue)")
            #expect(event.date > now, "already-passed events must not be scheduled")
        }
        for (a, b) in zip(s, s.dropFirst()) {
            #expect(b.event.date > a.event.date, "schedule must be strictly ordered in time")
        }
        // Full and new alternate, so twelve of them is about six months.
        let span = s.last!.event.date.timeIntervalSince(now) / 86_400
        #expect(span > 150 && span < 200, "12 syzygies should span ~177 d, got \(Int(span)) d")
    }

    /// Identifiers must be stable for a given instant, so a refresh replaces its own pending
    /// requests instead of accumulating a duplicate on every foreground.
    @Test func identifiersAreStableAcrossRefreshesAndUniqueWithinOne() {
        let a = MoonNotifications.schedule(from: utcDate(2026, 3, 1))
        let b = MoonNotifications.schedule(from: utcDate(2026, 3, 1).addingTimeInterval(3600))
        let common = Set(a.map(\.id)).intersection(b.map(\.id))
        #expect(common.count >= 10, "an hour later should reuse nearly every id, shared \(common.count)")
        #expect(Set(a.map(\.id)).count == a.count, "ids must be unique within one schedule")
        for (_, id) in a { #expect(id.hasPrefix("eph.moon."), "id \(id) must carry the feature prefix") }
    }

    @Test func scheduleStaysInsideTheSystemPendingCap() {
        // iOS keeps 64 pending local notifications and drops the rest silently.
        #expect(MoonNotifications.horizon <= 64)
        #expect(MoonNotifications.schedule(from: utcDate(2026, 1, 1)).count <= 64)
    }

    // MARK: - The time zone, which is the whole point

    @Test func componentsCarryUTCAndResolveBackToTheSameInstant() {
        let cal = Calendar(identifier: .gregorian)
        for date in MoonNotifications.schedule(from: utcDate(2026, 1, 1)).map(\.event.date) {
            let c = MoonNotifications.components(for: date)
            #expect(c.timeZone == TimeZone(secondsFromGMT: 0),
                    "components must carry UTC or the trigger fires at a wall-clock time")
            guard let resolved = cal.date(from: c) else {
                Issue.record("components did not resolve back to a date"); continue
            }
            // Components are minute-resolution, so the round trip is exact to within a minute.
            let drift = abs(resolved.timeIntervalSince(date))
            #expect(drift < 60, "round-trip drifted \(drift) s")
        }
    }

    /// The regression this design exists to prevent, stated directly: an event on the far side of a
    /// daylight-saving change must resolve to the same absolute instant it was built from.
    ///
    /// Local components would resolve an hour off here and nowhere else in the year.
    @Test func anEventAcrossADaylightSavingChangeKeepsItsAbsoluteInstant() {
        var uk = Calendar(identifier: .gregorian)
        uk.timeZone = TimeZone(identifier: "Europe/London")!

        // Straddles the 2026-03-29 spring-forward and the 2026-10-25 fall-back.
        for start in [utcDate(2026, 3, 20), utcDate(2026, 10, 18)] {
            for date in MoonNotifications.schedule(from: start, limit: 4).map(\.event.date) {
                let c = MoonNotifications.components(for: date)
                // Resolved through a DST-observing calendar, exactly as the system will.
                guard let resolved = uk.date(from: c) else {
                    Issue.record("no resolution for \(date)"); continue
                }
                let drift = abs(resolved.timeIntervalSince(date))
                let why = "\(date) resolved \(Int(drift / 60)) min away through Europe/London — "
                        + "components are being read as local wall-clock time"
                #expect(drift < 60, "\(why)")
            }
        }
    }

    // MARK: - Content

    @Test func contentNamesThePhaseAndItsSign() {
        for (event, _) in MoonNotifications.schedule(from: utcDate(2026, 3, 1), limit: 4) {
            let c = MoonNotifications.content(for: event)
            #expect(!c.title.isEmpty, "a notification with no title shows as a bare app name")
            #expect(!c.body.isEmpty)
            #expect(c.body.contains(event.sign.name),
                    "body \(c.body) should name the sign \(event.sign.name)")
        }
    }
}
