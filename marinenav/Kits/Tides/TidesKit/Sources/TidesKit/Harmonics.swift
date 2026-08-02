import Foundation

/// Harmonic tide synthesis and high/low finding. Pure, stateless.
///
/// Prediction form: Parker, *Tidal Analysis and Prediction*, NOAA Special
/// Publication NOS CO-OPS 3 (2007), §3.4.2 eq. (3.1)/(3.3):
///
///     h(t) = H₀ + Σ fᵢ·Hᵢ·cos( (V₀+u)ᵢ − κ′ᵢ )
///
/// Using GMT time with NOAA's `phase_GMT` (Schureman's G) makes the local-meridian
/// term vanish, which is the form used here.
///
/// MODEL CAVEAT: this is *astronomical* tide only. It does not model storm surge,
/// river discharge, barometric setup, seiche or wind — real water level routinely
/// departs from a harmonic prediction by tens of centimetres. Accuracy is also
/// bounded by how well the station's published constituent set represents it: at
/// stations with strong shallow-water overtides (e.g. upper Cook Inlet) NOAA's own
/// predictions use more constituents than it publishes, and no 37-constituent
/// synthesis — ours or anyone's — can reproduce them closely.
public enum Harmonics: Sendable {

    /// Predicted height above the station's datum at `date`, in the station's units.
    public static func height(_ station: Station, at date: Date) -> Double {
        let e = Astronomy.elements(at: date)
        let n = Nodal(nodeDeg: e.nDeg, perigeeDeg: e.pDeg)
        var h = station.meanWaterLevel
        for c in station.constituents {
            let arg = c.definition.equilibriumArgumentDeg(e, n) - c.greenwichPhaseDeg
            h += c.definition.nodeFactor(n) * c.amplitude * cos(Angle.radians(arg))
        }
        return h
    }

    /// Predicted heights at a regular cadence — cheaper than repeated `height`
    /// calls because the astronomy is recomputed per sample either way, but this
    /// keeps call sites simple and allocation-free per sample.
    public static func heights(_ station: Station, from start: Date,
                               count: Int, stepSeconds: Double) -> [Double] {
        precondition(count >= 0, "count must be >= 0")
        precondition(stepSeconds > 0, "stepSeconds must be > 0")
        return (0..<count).map {
            height(station, at: start.addingTimeInterval(Double($0) * stepSeconds))
        }
    }

    /// Rate of change of height, in station units per hour, by central difference.
    public static func slope(_ station: Station, at date: Date,
                             deltaSeconds: Double = 30) -> Double {
        let a = height(station, at: date.addingTimeInterval(-deltaSeconds))
        let b = height(station, at: date.addingTimeInterval(deltaSeconds))
        return (b - a) / (2 * deltaSeconds / 3600.0)
    }

    /// High and low waters in `[start, start + hours)`.
    ///
    /// Scans for sign changes of the slope, then bisects to `toleranceSeconds`.
    /// `stepMinutes` must be well below the shortest constituent period present;
    /// the 10-minute default is safe through M8 (≈3.1 h).
    public static func extremes(_ station: Station, start: Date, hours: Double,
                                stepMinutes: Double = 10,
                                toleranceSeconds: Double = 1) -> [TideEvent] {
        precondition(hours >= 0, "hours must be >= 0")
        precondition(stepMinutes > 0, "stepMinutes must be > 0")
        let step = stepMinutes * 60
        let n = Int((hours * 3600 / step).rounded(.up))
        guard n > 0 else { return [] }

        var events: [TideEvent] = []
        var prev = start
        var prevSlope = slope(station, at: prev)
        for k in 1...n {
            let t = start.addingTimeInterval(Double(k) * step)
            let s = slope(station, at: t)
            if prevSlope > 0 && s <= 0 {
                events.append(refine(station, prev, t, high: true, tolerance: toleranceSeconds))
            } else if prevSlope < 0 && s >= 0 {
                events.append(refine(station, prev, t, high: false, tolerance: toleranceSeconds))
            }
            prev = t
            prevSlope = s
        }
        let end = start.addingTimeInterval(hours * 3600)
        return events.filter { $0.date >= start && $0.date < end }
    }

    /// Bisect a bracketed slope sign change.
    private static func refine(_ station: Station, _ a: Date, _ b: Date,
                               high: Bool, tolerance: Double) -> TideEvent {
        var lo = a, hi = b
        while hi.timeIntervalSince(lo) > tolerance {
            let mid = Date(timeIntervalSince1970:
                (lo.timeIntervalSince1970 + hi.timeIntervalSince1970) / 2)
            // On the low side of a high water the slope is still positive.
            if (slope(station, at: mid) > 0) == high { lo = mid } else { hi = mid }
        }
        let t = Date(timeIntervalSince1970:
            (lo.timeIntervalSince1970 + hi.timeIntervalSince1970) / 2)
        return TideEvent(date: t, height: height(station, at: t),
                         unit: station.unit, kind: high ? .high : .low)
    }
}
