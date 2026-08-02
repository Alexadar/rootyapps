import Testing
import Foundation
import EphemerisKit

@Suite("Event timeline finders")
struct EventTimelineTests {
    let year = DateInterval(start: utc(2026, 1, 1), end: utc(2026, 12, 31, 23, 59))

    private func sep(_ a: CelestialBody, _ b: CelestialBody, _ d: Date) -> Double {
        AstroMath.separation(Ephemeris.longitude(of: a, at: d), Ephemeris.longitude(of: b, at: d))
    }

    @Test func sunIngressesTwelvePerYearAtSignBoundaries() {
        let evs = EventTimeline.allEvents(in: year, bodies: [.sun], include: [.ingress])
        #expect((11...13).contains(evs.count))
        for e in evs {
            let inSign = AstroMath.norm360(e.longitudeA).truncatingRemainder(dividingBy: 30)
            #expect(inSign < 0.01 || inSign > 29.99)   // lands exactly on a 30° boundary
            #expect(e.kind == .signIngress && e.sign != nil)
        }
        // Consecutive Sun ingresses advance the sign by one.
        let signs = evs.map { $0.sign!.rawValue }
        for i in 1..<signs.count { #expect((signs[i - 1] + 1) % 12 == signs[i]) }
    }

    @Test func lunationsAlternateAndAreCloseToSunOrOpposite() {
        let evs = EventTimeline.allEvents(in: year, include: [.lunation])
        let news = evs.filter { $0.kind == .newMoon }
        let fulls = evs.filter { $0.kind == .fullMoon }
        #expect((12...13).contains(news.count))
        #expect((12...13).contains(fulls.count))
        for e in news { #expect(sep(.moon, .sun, e.date) < 0.5) }
        for e in fulls { #expect(abs(sep(.moon, .sun, e.date) - 180) < 0.5) }
        // New and Full alternate through the year.
        for i in 1..<evs.count { #expect(evs[i - 1].kind != evs[i].kind) }
    }

    @Test func mundaneAspectsPerfectAtTheirAngle() {
        let evs = EventTimeline.allEvents(in: year, include: [.aspect])
        #expect(!evs.isEmpty)
        for e in evs {
            #expect(e.kind == .mundaneAspect)
            let s = sep(e.bodyA, e.bodyB!, e.date)
            #expect(abs(s - e.aspect!.angle) < 0.05)   // exact perfection
        }
    }

    @Test func marsNeptuneAspectExists() {
        let wide = DateInterval(start: utc(2025, 1, 1), end: utc(2027, 12, 31))
        let evs = EventTimeline.allEvents(in: wide, bodies: [.mars, .neptune], include: [.aspect])
        #expect(evs.contains { ($0.bodyA == .mars && $0.bodyB == .neptune) ||
                               ($0.bodyA == .neptune && $0.bodyB == .mars) })
    }

    @Test func mergedTimelineIsTimeOrdered() {
        let evs = EventTimeline.allEvents(in: year)
        #expect(evs.count > 50)
        for i in 1..<evs.count { #expect(evs[i - 1].date <= evs[i].date) }
    }
}
