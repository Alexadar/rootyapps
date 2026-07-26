import Foundation

/// Aurora visibility: the NOAA Kp → equatorward auroral-oval geomagnetic-latitude
/// "view line", plus helpers to reduce the NOAA OVATION probability grid.
///
/// Pure and deterministic. Latitudes are *geomagnetic*; the app states that honestly
/// rather than pretending to a city name. Oracle-tested against the NOAA table.
public enum Aurora {

    /// Equatorward-boundary geomagnetic latitude at which aurora may be visible,
    /// indexed by integer Kp 0…9 (NOAA aurora Kp→latitude table).
    public static let latitudeByKp: [Double] = [
        66.5, 64.5, 62.4, 60.4, 58.3, 56.3, 54.2, 52.2, 50.1, 48.1,
    ]

    /// Lowest geomagnetic latitude from which aurora may be seen for a raw Kp,
    /// linearly interpolated between the tabulated integer-Kp values and clamped 0…9.
    public static func equatorwardGeomagLatitude(kp: Double) -> Double {
        let k = min(max(kp, 0), 9)
        let lo = Int(k.rounded(.down))
        if lo >= 9 { return latitudeByKp[9] }
        let frac = k - Double(lo)
        return latitudeByKp[lo] + (latitudeByKp[lo + 1] - latitudeByKp[lo]) * frac
    }

    public static func viewLineDescription(kp: Double) -> String {
        let lat = equatorwardGeomagLatitude(kp: kp)
        return String(format: "Aurora may be visible down to %.0f° geomagnetic latitude.", lat)
    }

    // MARK: - OVATION probability grid

    /// One cell of the NOAA OVATION aurora nowcast: geographic coordinate + probability %.
    public struct OvationCell: Equatable, Sendable {
        public let longitude: Double  // 0…359 (geographic)
        public let latitude: Double   // −90…90 (geographic)
        public let probability: Int   // 0…100 (%)
        public init(longitude: Double, latitude: Double, probability: Int) {
            self.longitude = longitude; self.latitude = latitude; self.probability = probability
        }
    }

    /// Highest aurora probability anywhere in the grid.
    public static func maxProbability(in cells: [OvationCell]) -> Int {
        cells.map(\.probability).max() ?? 0
    }

    /// Aurora probability nearest a geographic point (grid is 1°×1°; longitude wraps 0…360).
    public static func probability(atLatitude lat: Double, longitude lon: Double,
                                   in cells: [OvationCell]) -> Int? {
        let wrapped = (lon.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return cells.min { a, b in
            angularCost(a, lat, wrapped) < angularCost(b, lat, wrapped)
        }?.probability
    }

    private static func angularCost(_ c: OvationCell, _ lat: Double, _ lon: Double) -> Double {
        let dLat = c.latitude - lat
        var dLon = abs(c.longitude - lon)
        if dLon > 180 { dLon = 360 - dLon }
        return dLat * dLat + dLon * dLon
    }
}
