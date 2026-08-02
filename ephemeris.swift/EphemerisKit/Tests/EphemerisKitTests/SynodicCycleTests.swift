import Testing
import Foundation
import EphemerisKit

@Suite("Synodic cycle (Mercury phases)")
struct SynodicCycleTests {

    private let year2026 = DateInterval(start: utc(2026, 1, 1), end: utc(2026, 12, 31, 23, 59))

    private func sunSep(_ body: CelestialBody, _ date: Date) -> Double {
        AstroMath.separation(Ephemeris.longitude(of: body, at: date),
                             Ephemeris.longitude(of: .sun, at: date))
    }

    @Test func mercuryEventCountsPerYear() {
        let evs = SynodicCycle.events(for: .mercury, in: year2026)
        let inf = evs.filter { $0.kind == .inferiorConjunction }
        let sup = evs.filter { $0.kind == .superiorConjunction }
        let sr = evs.filter { $0.kind == .stationRetrograde }
        let sd = evs.filter { $0.kind == .stationDirect }
        // Mercury: ~3 synodic cycles per year (occasionally 4).
        #expect((3...4).contains(inf.count))
        #expect((3...4).contains(sup.count))
        #expect(sr.count == sd.count)
        #expect((3...4).contains(sr.count))
    }

    @Test func eventsAreTimeOrdered() {
        let evs = SynodicCycle.events(for: .mercury, in: year2026)
        #expect(evs.count > 4)
        for i in 1..<evs.count { #expect(evs[i - 1].date <= evs[i].date) }
    }

    @Test func conjunctionsAreCloseToSunAndCorrectlyTyped() {
        let evs = SynodicCycle.events(for: .mercury, in: year2026)
        for e in evs where e.kind == .inferiorConjunction {
            #expect(sunSep(.mercury, e.date) < 0.5)
            #expect(Ephemeris.isRetrograde(.mercury, at: e.date))   // inferior ⇒ retrograde
        }
        for e in evs where e.kind == .superiorConjunction {
            #expect(sunSep(.mercury, e.date) < 0.5)
            #expect(!Ephemeris.isRetrograde(.mercury, at: e.date))  // superior ⇒ direct
        }
    }

    @Test func stationsHaveNearZeroMotionWithSignFlip() {
        let evs = SynodicCycle.events(for: .mercury, in: year2026)
        let stations = evs.filter { $0.kind == .stationRetrograde || $0.kind == .stationDirect }
        #expect(!stations.isEmpty)
        for s in stations {
            #expect(abs(Ephemeris.dailyMotion(of: .mercury, at: s.date)) < 0.05)
            let before = Ephemeris.dailyMotion(of: .mercury, at: s.date.addingTimeInterval(-3 * 86_400))
            let after = Ephemeris.dailyMotion(of: .mercury, at: s.date.addingTimeInterval(3 * 86_400))
            #expect((before < 0) != (after < 0))   // genuine U-turn
            if s.kind == .stationRetrograde { #expect(before > 0 && after < 0) }
            else { #expect(before < 0 && after > 0) }
        }
    }

    /// The user's four boundary events all occur for Mercury within a year.
    @Test func theFourMercuryPhaseBoundariesExist() {
        let evs = SynodicCycle.events(for: .mercury, in: year2026)
        #expect(evs.contains { $0.kind == .inferiorConjunction })
        #expect(evs.contains { $0.kind == .stationDirect })
        #expect(evs.contains { $0.kind == .superiorConjunction })
        #expect(evs.contains { $0.kind == .stationRetrograde })
    }

    @Test func currentPhaseBracketsTheMoment() {
        let phase = SynodicCycle.currentPhase(of: .mercury, at: utc(2026, 6, 21))
        #expect(phase.start != nil)
        #expect(phase.end != nil)
        if let s = phase.start, let e = phase.end {
            #expect(s.date <= utc(2026, 6, 21))
            #expect(e.date > utc(2026, 6, 21))
        }
    }

    /// Generalization: a superior planet yields conjunctions, oppositions and stations.
    @Test func marsHasOppositionAndStations() {
        let interval = DateInterval(start: utc(2025, 1, 1), end: utc(2027, 12, 31))
        let evs = SynodicCycle.events(for: .mars, in: interval)
        #expect(evs.contains { $0.kind == .opposition })
        #expect(evs.contains { $0.kind == .conjunction })
        #expect(evs.contains { $0.kind == .stationRetrograde })
        #expect(evs.contains { $0.kind == .stationDirect })
        for e in evs where e.kind == .opposition {
            #expect(abs(sunSep(.mars, e.date) - 180) < 0.5)
        }
    }
}
