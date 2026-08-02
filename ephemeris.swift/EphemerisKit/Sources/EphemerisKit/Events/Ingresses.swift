import Foundation

/// Detects the exact instant a body crosses a 30° sign boundary (handles forward
/// and retrograde crossings, and the Pisces→Aries 0°/360° wrap).
enum Ingresses {
    static func events(for body: CelestialBody, in interval: DateInterval) -> [AstroEvent] {
        var out: [AstroEvent] = []
        let step = 86_400.0
        var t = interval.start
        var prevLon = Ephemeris.longitude(of: body, at: t)
        var prevSign = Int(AstroMath.norm360(prevLon) / 30)
        t = t.addingTimeInterval(step)

        while t <= interval.end {
            let lon = Ephemeris.longitude(of: body, at: t)
            let sign = Int(AstroMath.norm360(lon) / 30)
            if sign != prevSign {
                let forward = AstroMath.norm180(lon - prevLon) > 0
                // Boundary degree crossed: entering `sign` forward → sign*30; retrograde → prevSign*30.
                let boundary = Double((forward ? sign : prevSign)) * 30
                let root = RootFinding.refine(t.addingTimeInterval(-step), t) {
                    AstroMath.norm180(Ephemeris.longitude(of: body, at: $0) - boundary)
                }
                let lonAtRoot = Ephemeris.longitude(of: body, at: root)
                out.append(AstroEvent(kind: .signIngress, date: root, bodyA: body,
                                      longitudeA: lonAtRoot,
                                      sign: ZodiacSign(rawValue: sign)!,
                                      retroA: Ephemeris.isRetrograde(body, at: root)))
            }
            prevLon = lon; prevSign = sign
            t = t.addingTimeInterval(step)
        }
        return out
    }
}
