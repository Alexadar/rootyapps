import SwiftUI
import EphemerisKit

/// Drives the whole app: a chosen moment → positions, aspects, and the synodic cycle.
@MainActor
final class ChartViewModel: ObservableObject {
    @Published var date: Date
    @Published var utcOffsetHours: Double
    @Published var orbFactor: Double = 1.0
    @Published var cycleBody: CelestialBody = .mercury

    @Published private(set) var positions: [BodyPosition] = []
    @Published private(set) var aspects: [DetectedAspect] = []
    @Published private(set) var cyclePhase: SynodicPhase?
    @Published private(set) var upcomingEvents: [SynodicEvent] = []
    @Published private(set) var timelineEvents: [AstroEvent] = []

    init() {
        date = Date()
        utcOffsetHours = Double(TimeZone.current.secondsFromGMT()) / 3600.0
        recompute()
    }

    /// The chosen wall-clock numbers reinterpreted at `utcOffsetHours` → an absolute UTC instant
    /// (matching the demo: `Date.UTC(Y,Mo,D,H,Mi) − offset`).
    var instant: Date {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = .current
        let c = local.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let asUTC = utc.date(from: c) ?? date
        return asUTC.addingTimeInterval(-utcOffsetHours * 3600)
    }

    func recompute() {
        let t = instant
        positions = CelestialBody.allCases.map {
            BodyPosition(body: $0,
                         longitude: Ephemeris.longitude(of: $0, at: t),
                         speed: Ephemeris.dailyMotion(of: $0, at: t))
        }
        aspects = Aspects.detect(in: positions, orbFactor: orbFactor)
        cyclePhase = SynodicCycle.currentPhase(of: cycleBody, at: t)
        upcomingEvents = SynodicCycle.nextEvents(of: cycleBody, from: t, count: 6)
        let window = DateInterval(start: t.addingTimeInterval(-30 * 86_400),
                                  end: t.addingTimeInterval(120 * 86_400))
        timelineEvents = EventTimeline.allEvents(in: window)
    }
}
