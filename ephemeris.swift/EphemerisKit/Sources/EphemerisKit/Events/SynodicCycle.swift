import Foundation

/// Finds the synodic-cycle events of a body relative to the Sun — conjunctions
/// (inferior/superior), oppositions, retrograde/direct stations ("U-turns") and
/// greatest elongations — by root-finding on the ephemeris. Generalized to any body.
public enum SynodicCycle {

    // MARK: Public API

    /// All synodic events of `body` within `interval`, time-ordered.
    public static func events(for body: CelestialBody, in interval: DateInterval) -> [SynodicEvent] {
        guard body != .sun, body != .moon else { return [] }
        var out: [SynodicEvent] = []
        let step = 86_400.0 // 1 day
        var t = interval.start

        var prev = sample(body, t)
        t = t.addingTimeInterval(step)
        while t <= interval.end {
            let cur = sample(body, t)
            let lo = t.addingTimeInterval(-step), hi = t

            // Conjunction / opposition (zero of relative longitude / its 180° shift).
            if RootFinding.crossesZero(prev.rel, cur.rel) {
                let root = RootFinding.refine(lo, hi) { relativeLongitude(body, $0) }
                let retro = Ephemeris.isRetrograde(body, at: root)
                let kind: SynodicEvent.Kind = body.isInferior
                    ? (retro ? .inferiorConjunction : .superiorConjunction)
                    : .conjunction
                out.append(SynodicEvent(kind: kind, date: root,
                                        longitude: Ephemeris.longitude(of: body, at: root)))
            }
            if body.isSuperior, RootFinding.crossesZero(prev.opp, cur.opp) {
                let root = RootFinding.refine(lo, hi) { oppositionFunction(body, $0) }
                out.append(SynodicEvent(kind: .opposition, date: root,
                                        longitude: Ephemeris.longitude(of: body, at: root)))
            }

            // Station: body's own longitude rate changes sign.
            if RootFinding.crossesZero(prev.motion, cur.motion) {
                let root = RootFinding.refine(lo, hi) { Ephemeris.dailyMotion(of: body, at: $0) }
                let kind: SynodicEvent.Kind = prev.motion > 0 ? .stationRetrograde : .stationDirect
                out.append(SynodicEvent(kind: kind, date: root,
                                        longitude: Ephemeris.longitude(of: body, at: root)))
            }

            // Greatest elongation (inner planets): relative-longitude rate changes sign.
            if body.isInferior, RootFinding.crossesZero(prev.relMotion, cur.relMotion) {
                let root = RootFinding.refine(lo, hi) { relativeMotion(body, $0) }
                let east = relativeLongitude(body, root) > 0
                out.append(SynodicEvent(kind: east ? .greatestElongationEast : .greatestElongationWest,
                                        date: root,
                                        longitude: Ephemeris.longitude(of: body, at: root)))
            }

            prev = cur
            t = t.addingTimeInterval(step)
        }
        return out.sorted { $0.date < $1.date }
    }

    /// The phase `date` falls in, plus the bracketing events.
    public static func currentPhase(of body: CelestialBody, at date: Date) -> SynodicPhase {
        let window = approxSynodicPeriodDays(body) * 1.4 * 86_400
        let evs = events(for: body, in: DateInterval(start: date.addingTimeInterval(-window),
                                                     end: date.addingTimeInterval(window)))
        let prev = evs.last { $0.date <= date }
        let next = evs.first { $0.date > date }
        let retro = Ephemeris.isRetrograde(body, at: date)

        var title = retro ? "Retrograde" : "Direct"
        var visibility: SynodicPhase.Visibility?
        if body.isInferior {
            let evening = relativeLongitude(body, date) > 0
            visibility = evening ? .eveningStar : .morningStar
            let star = evening ? "Evening star (Epimethean)" : "Morning star (Promethean)"
            title = "\(star) · \(retro ? "retrograde" : "direct")"
        }
        let detail = "\(prev?.kind.short ?? "—") → \(next?.kind.short ?? "—")"

        var dayIn: Int?, length: Int?
        if let p = prev {
            dayIn = Int(date.timeIntervalSince(p.date) / 86_400)
            if let n = next { length = Int(n.date.timeIntervalSince(p.date) / 86_400) }
        }
        return SynodicPhase(body: body, title: title, detail: detail, retrograde: retro,
                            visibility: visibility,
                            start: prev, end: next, dayInPhase: dayIn, phaseLengthDays: length)
    }

    /// The next `count` events on or after `from`.
    public static func nextEvents(of body: CelestialBody, from: Date, count: Int) -> [SynodicEvent] {
        let window = approxSynodicPeriodDays(body) * 2.6 * 86_400
        let evs = events(for: body, in: DateInterval(start: from, end: from.addingTimeInterval(window)))
        return Array(evs.filter { $0.date >= from }.prefix(count))
    }

    public static func approxSynodicPeriodDays(_ body: CelestialBody) -> Double {
        switch body {
        case .mercury: 116; case .venus: 584; case .mars: 780; case .jupiter: 399
        case .saturn: 378; case .uranus: 370; case .neptune: 368; case .pluto: 367
        case .sun, .moon: 365
        }
    }

    // MARK: Internals

    private struct Sample { let rel, opp, motion, relMotion: Double }

    private static func sample(_ body: CelestialBody, _ t: Date) -> Sample {
        Sample(rel: relativeLongitude(body, t),
               opp: oppositionFunction(body, t),
               motion: Ephemeris.dailyMotion(of: body, at: t),
               relMotion: relativeMotion(body, t))
    }

    /// Signed body−Sun longitude difference, (-180,180]. Zero at conjunction.
    private static func relativeLongitude(_ body: CelestialBody, _ t: Date) -> Double {
        RootFinding.signedSeparation(body, .sun, at: t)
    }

    /// Zero at opposition.
    private static func oppositionFunction(_ body: CelestialBody, _ t: Date) -> Double {
        AstroMath.norm180(relativeLongitude(body, t) - 180)
    }

    /// Rate of relative longitude (deg/day). Zero at greatest elongation.
    private static func relativeMotion(_ body: CelestialBody, _ t: Date) -> Double {
        Ephemeris.dailyMotion(of: body, at: t) - Ephemeris.dailyMotion(of: .sun, at: t)
    }
}
