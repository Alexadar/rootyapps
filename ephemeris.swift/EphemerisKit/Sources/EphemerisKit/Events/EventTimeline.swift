import Foundation

/// Merges all event finders (synodic, ingresses, lunations, mundane aspects) into one
/// time-ordered stream, filterable by `EventClass`.
public enum EventTimeline {
    public static func allEvents(in interval: DateInterval,
                                 bodies: [CelestialBody] = CelestialBody.allCases,
                                 include: Set<EventClass> = Set(EventClass.allCases)) -> [AstroEvent] {
        var out: [AstroEvent] = []

        // Sun-relative synodic events (conjunctions/oppositions/stations/elongations).
        let synodicClasses: Set<EventClass> = [.conjunction, .opposition, .station, .elongation]
        if !include.isDisjoint(with: synodicClasses) {
            for b in bodies where b != .sun && b != .moon {
                for se in SynodicCycle.events(for: b, in: interval) {
                    let ev = mapSynodic(se, body: b)
                    if include.contains(ev.eventClass) { out.append(ev) }
                }
            }
        }

        if include.contains(.ingress) {
            for b in bodies where b != .moon {   // Moon ingresses are too frequent for a timeline
                out += Ingresses.events(for: b, in: interval)
            }
        }

        if include.contains(.lunation) {
            out += Lunations.events(in: interval)
        }

        if include.contains(.aspect) {
            let planetSet = bodies.filter { $0 != .sun && $0 != .moon }
            out += MundaneAspects.events(bodies: planetSet, in: interval)
        }

        return out.sorted { $0.date < $1.date }
    }

    private static func mapSynodic(_ e: SynodicEvent, body: CelestialBody) -> AstroEvent {
        let kind: AstroEvent.Kind
        switch e.kind {
        case .inferiorConjunction: kind = .inferiorConjunction
        case .superiorConjunction: kind = .superiorConjunction
        case .conjunction: kind = .conjunction
        case .opposition: kind = .opposition
        case .stationRetrograde: kind = .stationRetrograde
        case .stationDirect: kind = .stationDirect
        case .greatestElongationEast: kind = .greatestElongationEast
        case .greatestElongationWest: kind = .greatestElongationWest
        }
        let isStation = kind == .stationRetrograde || kind == .stationDirect
        return AstroEvent(kind: kind, date: e.date, bodyA: body, bodyB: isStation ? nil : .sun,
                          longitudeA: e.longitude,
                          sign: ZodiacSign.from(longitude: e.longitude),
                          retroA: Ephemeris.isRetrograde(body, at: e.date))
    }
}
