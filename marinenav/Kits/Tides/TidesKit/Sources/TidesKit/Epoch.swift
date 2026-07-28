import Foundation

/// Conversions between the three published forms of a constituent's epoch
/// (phase lag). Pure, stateless.
///
/// Source: Parker, *Tidal Analysis and Prediction*, NOAA Special Publication
/// NOS CO-OPS 3 (2007), §3.4.2 eq. (3.2), p. 93:
///
///     κ′ ( = g ) = κ + p·L − a·S/15
///     κ + p·L    = G
///
/// where
/// - `κ` is the epoch relative to the moon's transit over the **station**,
/// - `g` (= κ′) is the epoch on the **local time meridian**,
/// - `G` is the epoch on the **Greenwich** meridian (NOAA's `phase_GMT`),
/// - `L` = west longitude of the station (negative for east longitude),
/// - `S` = west longitude of the local time meridian,
/// - `a` = the constituent's speed in °/hour,
/// - `p` = the **species**: 0 long-period, 1 diurnal, 2 semidiurnal, 3 terdiurnal,
///   4 quarter-diurnal, …
///
/// Verified against NOAA's own published `phase_GMT`/`phase_local` pairs for all
/// 33 non-zero constituents at station 9414290: agreement ≤ 0.09°, inside NOAA's
/// own 0.1° publication rounding.
public enum Epoch: Sendable {

    /// Species of a constituent — the multiple of the mean-solar hour angle in
    /// its argument (`p` in Parker eq. 3.2).
    public static func species(_ definition: ConstituentDefinition) -> Int {
        Int(definition.coefficients.0.rounded())
    }

    /// Greenwich epoch `G` → local-time-meridian epoch `g` (= κ′).
    ///
    /// - Parameter timeMeridianWestDeg: `S`, west longitude of the local time
    ///   meridian (e.g. 120 for Pacific Standard Time).
    public static func localFromGreenwich(greenwichDeg G: Double,
                                          speedDegPerHour a: Double,
                                          timeMeridianWestDeg S: Double) -> Double {
        Angle.normalize(G - a * S / 15.0)
    }

    /// Local-time-meridian epoch `g` → Greenwich epoch `G`.
    public static func greenwichFromLocal(localDeg g: Double,
                                          speedDegPerHour a: Double,
                                          timeMeridianWestDeg S: Double) -> Double {
        Angle.normalize(g + a * S / 15.0)
    }

    /// Station epoch `κ` → Greenwich epoch `G`:  `G = κ + p·L`.
    ///
    /// - Parameter stationWestLongitudeDeg: `L`, **west** longitude of the
    ///   station — negative for a station in east longitude.
    public static func greenwichFromStation(stationDeg kappa: Double,
                                            species p: Int,
                                            stationWestLongitudeDeg L: Double) -> Double {
        Angle.normalize(kappa + Double(p) * L)
    }

    /// Greenwich epoch `G` → station epoch `κ`:  `κ = G − p·L`.
    public static func stationFromGreenwich(greenwichDeg G: Double,
                                            species p: Int,
                                            stationWestLongitudeDeg L: Double) -> Double {
        Angle.normalize(G - Double(p) * L)
    }
}
