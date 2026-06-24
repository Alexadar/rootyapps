import Foundation

/// New Moon (Sun–Moon conjunction) and Full Moon (opposition) instants.
enum Lunations {
    static func events(in interval: DateInterval) -> [AstroEvent] {
        var out: [AstroEvent] = []
        let step = 86_400.0
        var t = interval.start

        func rel(_ at: Date) -> Double { RootFinding.signedSeparation(.moon, .sun, at: at) }
        func opp(_ at: Date) -> Double { AstroMath.norm180(rel(at) - 180) }

        var prevRel = rel(t), prevOpp = opp(t)
        t = t.addingTimeInterval(step)
        while t <= interval.end {
            let curRel = rel(t), curOpp = opp(t)
            let lo = t.addingTimeInterval(-step), hi = t

            if RootFinding.crossesZero(prevRel, curRel) {
                let root = RootFinding.refine(lo, hi, rel)
                let lon = Ephemeris.longitude(of: .moon, at: root)
                out.append(AstroEvent(kind: .newMoon, date: root, bodyA: .moon, bodyB: .sun,
                                      longitudeA: lon, longitudeB: Ephemeris.longitude(of: .sun, at: root),
                                      sign: ZodiacSign.from(longitude: lon)))
            }
            if RootFinding.crossesZero(prevOpp, curOpp) {
                let root = RootFinding.refine(lo, hi, opp)
                let lon = Ephemeris.longitude(of: .moon, at: root)
                out.append(AstroEvent(kind: .fullMoon, date: root, bodyA: .moon, bodyB: .sun,
                                      longitudeA: lon, longitudeB: Ephemeris.longitude(of: .sun, at: root),
                                      sign: ZodiacSign.from(longitude: lon)))
            }
            prevRel = curRel; prevOpp = curOpp
            t = t.addingTimeInterval(step)
        }
        return out
    }
}
