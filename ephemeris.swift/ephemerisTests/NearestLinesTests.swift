import Testing
import Foundation
import EphemerisKit
@testable import Ephemeris

/// The "near you" ranking.
///
/// The property that matters most is not the ordering — it is that a **circumpolar line reports as
/// absent** rather than as a distance. A body that never touches the horizon at these latitudes has
/// no AC or DC line anywhere; giving it a number would tell someone they are 400 km from a place
/// they could move to, which does not exist.
@Suite("Nearest lines")
struct NearestLinesTests {

    private let london = GeoLocation(latitude: 51.5074, longitude: -0.1278, name: "London")

    private func chartInstant() -> Date {
        var c = DateComponents(); c.year = 1990; c.month = 6; c.day = 15; c.hour = 12
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.date(from: c)!
    }

    // MARK: - Ordering

    @Test func linesAreRankedNearestFirstWithAbsentOnesLast() {
        let lines = AstroCartography.lines(at: chartInstant())
        let ranked = NearestLines.ranked(lines, observer: london, limit: 40)
        #expect(!ranked.isEmpty)

        let present = ranked.filter { !$0.absent }
        let absent = ranked.filter(\.absent)

        for (a, b) in zip(present, present.dropFirst()) {
            #expect((a.kilometres ?? 0) <= (b.kilometres ?? 0),
                    "\(a.id) at \(a.kilometres ?? 0) km precedes \(b.id) at \(b.kilometres ?? 0)")
        }
        // Every absent entry must come after every present one.
        if let firstAbsent = ranked.firstIndex(where: \.absent) {
            #expect(!ranked[firstAbsent...].contains { !$0.absent },
                    "a present line was ranked after an absent one")
        }
        #expect(absent.allSatisfy { $0.kilometres == nil })
    }

    @Test func theLimitIsRespected() {
        let lines = AstroCartography.lines(at: chartInstant())
        #expect(NearestLines.ranked(lines, observer: london, limit: 5).count == 5)
        #expect(NearestLines.ranked(lines, observer: london, limit: 3).count == 3)
    }

    // MARK: - Distances are real

    /// An MC line is a meridian, so its distance from an observer is a pure east–west separation
    /// and can be checked independently against the haversine along that parallel.
    @Test func meridianDistancesAgreeWithAnIndependentCalculation() {
        let lines = AstroCartography.lines(at: chartInstant(),
                                           bodies: [.sun], angles: [.midheaven])
        guard let mc = lines.first, let meridian = mc.meridian else {
            Issue.record("expected a Sun MC meridian"); return
        }
        let ranked = NearestLines.ranked(lines, observer: london)
        guard let p = ranked.first, let km = p.kilometres else {
            Issue.record("MC line reported absent"); return
        }
        // Nearest point on a meridian is at the observer's own latitude.
        let independent = GeoDistance.kilometres(from: (london.latitude, london.longitude),
                                                 to: (london.latitude, meridian))
        // The Kit samples one point per degree of latitude, so the sampled nearest point can sit up
        // to half a degree away in latitude — about 55 km.
        #expect(abs(km - independent) < 60,
                "ranked \(Int(km)) km vs independent \(Int(independent)) km")
    }

    @Test func aZeroDistanceIsPossibleWhenStandingOnALine() {
        let lines = AstroCartography.lines(at: chartInstant(), bodies: [.sun], angles: [.midheaven])
        guard let meridian = lines.first?.meridian else { Issue.record("no meridian"); return }
        let onTheLine = GeoLocation(latitude: 51.5, longitude: meridian)
        guard let p = NearestLines.ranked(lines, observer: onTheLine).first,
              let km = p.kilometres else { Issue.record("absent"); return }
        #expect(km < 60, "standing on the line should read ~0 km, got \(Int(km))")
    }

    // MARK: - Absence

    /// ⚠️ The honest state. At a high latitude some bodies are circumpolar, so their AC/DC lines do
    /// not exist and `AstroCartography` returns no points. That must surface as `absent`, not as a
    /// distance and not as a silently dropped row.
    @Test func circumpolarLinesReportAbsentRatherThanADistance() {
        // A band ENTIRELY inside the polar cap, so absence is produced rather than hoped for.
        // In mid-June the Sun's declination is ~+23.4°, so its horizon lines stop existing beyond
        // 90 − 23.4 ≈ 66.6° — every latitude in this band is past that limit.
        let polar = LatitudeBand(south: 80, north: 89, step: 1)
        let lines = AstroCartography.lines(at: chartInstant(),
                                           bodies: CelestialBody.allCases,
                                           angles: [.ascendant, .descendant],
                                           band: polar)
        let empties = lines.filter(\.isEmpty)
        guard !empties.isEmpty else {
            Issue.record("a band at 80–89° must contain circumpolar bodies — none were empty")
            return
        }
        let ranked = NearestLines.ranked(lines, observer: london, limit: 99)
        for empty in empties {
            guard let p = ranked.first(where: { $0.body == empty.body && $0.angle == empty.angle })
            else { Issue.record("\(empty.body.name) \(empty.angle) vanished from the ranking"); continue }
            #expect(p.absent, "\(empty.body.name) \(empty.angle) has no line but reported a distance")
        }
    }

    /// Nothing may be silently dropped: every line handed in appears in the ranking when the limit
    /// allows it, so a user filtering by body always sees what they selected.
    @Test func everyLineSurvivesTheRankingWhenTheLimitAllows() {
        let lines = AstroCartography.lines(at: chartInstant(),
                                           bodies: [.sun, .moon, .mars], angles: AstroCartoAngle.allCases)
        let ranked = NearestLines.ranked(lines, observer: london, limit: 99)
        #expect(ranked.count == lines.count,
                "handed \(lines.count) lines, ranking returned \(ranked.count)")
    }
}
