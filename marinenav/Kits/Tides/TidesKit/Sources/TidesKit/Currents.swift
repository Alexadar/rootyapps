import Foundation

/// Tidal-current synthesis: major-axis velocity, slack water and maximum
/// flood/ebb. Pure, stateless.
///
/// Same harmonic machinery as `Harmonics`, applied to NOAA's published
/// current constants (`majorAmplitude` cm/s, `majorPhaseGMT`).
///
///     V(t) = V_mean + Σ fᵢ·Aᵢ·cos( (V₀+u)ᵢ − Gᵢ )
///
/// Sign convention: **positive is flood**, negative is ebb — matching NOAA's
/// published `Velocity_Major`.
///
/// MODEL CAVEAT: this is the *major-axis* (rectilinear) component only. In open
/// water the current is rotary and the minor-axis component is not modelled here;
/// NOAA publishes minor amplitudes as zero for the rectilinear stations this is
/// designed for. As with heights, wind and river flow are not modelled.
public enum Currents: Sendable {

    /// Predicted major-axis velocity in cm/s at `date`. Positive = flood.
    public static func velocity(_ station: CurrentStation, at date: Date) -> Double {
        let e = Astronomy.elements(at: date)
        let n = Nodal(nodeDeg: e.nDeg, perigeeDeg: e.pDeg)
        var v = station.meanFlowCMS
        for c in station.constituents {
            let arg = c.definition.equilibriumArgumentDeg(e, n) - c.greenwichPhaseDeg
            v += c.definition.nodeFactor(n) * c.amplitude * cos(Angle.radians(arg))
        }
        return v
    }

    /// Rate of change of velocity, cm/s per hour, by central difference.
    public static func acceleration(_ station: CurrentStation, at date: Date,
                                    deltaSeconds: Double = 30) -> Double {
        let a = velocity(station, at: date.addingTimeInterval(-deltaSeconds))
        let b = velocity(station, at: date.addingTimeInterval(deltaSeconds))
        return (b - a) / (2 * deltaSeconds / 3600.0)
    }

    /// Slack waters and maximum floods/ebbs in `[start, start + hours)`.
    ///
    /// Slacks are zero crossings of the velocity; maxima are zero crossings of
    /// its derivative. Both are bisected to `toleranceSeconds`.
    public static func events(_ station: CurrentStation, start: Date, hours: Double,
                              stepMinutes: Double = 10,
                              toleranceSeconds: Double = 1) -> [CurrentEvent] {
        precondition(hours >= 0, "hours must be >= 0")
        precondition(stepMinutes > 0, "stepMinutes must be > 0")
        let step = stepMinutes * 60
        let n = Int((hours * 3600 / step).rounded(.up))
        guard n > 0 else { return [] }

        var out: [CurrentEvent] = []
        var prev = start
        var prevV = velocity(station, at: prev)
        var prevA = acceleration(station, at: prev)

        for k in 1...n {
            let t = start.addingTimeInterval(Double(k) * step)
            let v = velocity(station, at: t)
            let a = acceleration(station, at: t)

            if (prevV > 0 && v <= 0) || (prevV < 0 && v >= 0) {
                let z = bisect(prev, t) { (velocity(station, at: $0) > 0) == (prevV > 0) }
                out.append(CurrentEvent(date: z, velocityCMS: velocity(station, at: z),
                                        phase: .slack))
            }
            if (prevA > 0 && a <= 0) || (prevA < 0 && a >= 0) {
                let z = bisect(prev, t) { (acceleration(station, at: $0) > 0) == (prevA > 0) }
                let vv = velocity(station, at: z)
                out.append(CurrentEvent(date: z, velocityCMS: vv,
                                        phase: vv >= 0 ? .flood : .ebb))
            }
            prev = t; prevV = v; prevA = a
        }
        let end = start.addingTimeInterval(hours * 3600)
        return out.filter { $0.date >= start && $0.date < end }
            .sorted { $0.date < $1.date }
    }

    /// Bisect `[a, b]` for the point where `keepLow` flips from true to false.
    private static func bisect(_ a: Date, _ b: Date, _ keepLow: (Date) -> Bool) -> Date {
        var lo = a, hi = b
        while hi.timeIntervalSince(lo) > 1 {
            let mid = Date(timeIntervalSince1970:
                (lo.timeIntervalSince1970 + hi.timeIntervalSince1970) / 2)
            if keepLow(mid) { lo = mid } else { hi = mid }
        }
        return Date(timeIntervalSince1970:
            (lo.timeIntervalSince1970 + hi.timeIntervalSince1970) / 2)
    }
}
