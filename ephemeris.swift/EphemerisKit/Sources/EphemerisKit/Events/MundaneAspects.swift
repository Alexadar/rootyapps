import Foundation

/// Exact perfection dates of planet↔planet aspects (conjunction/sextile/square/
/// trine/opposition) for every unordered pair in `bodies`.
enum MundaneAspects {
    static func events(bodies: [CelestialBody],
                       aspects: [AspectType] = AspectType.all,
                       in interval: DateInterval) -> [AstroEvent] {
        var out: [AstroEvent] = []
        let step = 86_400.0

        for i in 0..<bodies.count {
            for j in (i + 1)..<bodies.count {
                let (lo, hi) = EventCatalog.orderedPair(bodies[i], bodies[j])
                for asp in aspects {
                    // A 0° and 180° aspect has one target; 60/90/120 perfect at ±angle.
                    let targets: [Double] = asp.angle == 0 || asp.angle == 180
                        ? [asp.angle] : [asp.angle, -asp.angle]
                    for target in targets {
                        out += scan(lo, hi, asp, target, interval, step)
                    }
                }
            }
        }
        return out
    }

    private static func scan(_ lo: CelestialBody, _ hi: CelestialBody, _ asp: AspectType,
                             _ target: Double, _ interval: DateInterval, _ step: Double) -> [AstroEvent] {
        var out: [AstroEvent] = []
        func f(_ at: Date) -> Double {
            AstroMath.norm180(RootFinding.signedSeparation(lo, hi, at: at) - target)
        }
        var t = interval.start
        var prev = f(t)
        t = t.addingTimeInterval(step)
        while t <= interval.end {
            let cur = f(t)
            if RootFinding.crossesZero(prev, cur) {
                let root = RootFinding.refine(t.addingTimeInterval(-step), t, f)
                let lonA = Ephemeris.longitude(of: lo, at: root)
                out.append(AstroEvent(kind: .mundaneAspect, date: root, bodyA: lo, bodyB: hi,
                                      aspect: asp, longitudeA: lonA,
                                      longitudeB: Ephemeris.longitude(of: hi, at: root),
                                      sign: ZodiacSign.from(longitude: lonA),
                                      retroA: Ephemeris.isRetrograde(lo, at: root),
                                      retroB: Ephemeris.isRetrograde(hi, at: root)))
            }
            prev = cur
            t = t.addingTimeInterval(step)
        }
        return out
    }
}
