import Foundation
import CoreGraphics

/// Equirectangular projection, and the antimeridian problem it creates.
///
/// ## Why equirectangular, and why not MapKit
///
/// Astrocartography lines are loci in latitude/longitude: an MC line is a meridian, an AC line is a
/// curve solved per latitude. Equirectangular maps longitude and latitude **linearly** onto x and
/// y, so a meridian is a vertical line and no reprojection maths is needed anywhere — the geometry
/// the Kit already computes is the geometry drawn.
///
/// MapKit is the obvious alternative and is wrong here for two reasons: its tiles need a network,
/// and this app is offline and paid-upfront; and its cartography is a light, labelled street map
/// that would sit inside a deep-space visual language like a photograph in a woodcut.
///
/// ## The antimeridian
///
/// A line that runs off the right edge at +180° reappears at the left edge at −180°. Joined
/// naively, the two ends are connected by a horizontal stroke straight across the entire map — a
/// line that exists nowhere on Earth and is instantly recognisable as a bug once you know to look
/// for it. `segments(_:)` splits a path wherever consecutive points jump more than half the world,
/// so the two halves are drawn as separate strokes and nothing is invented between them.
enum MapProjection {

    /// Where a coordinate lands in a unit square: x 0…1 west→east, y 0…1 north→south.
    ///
    /// Latitude is clamped to ±90 and longitude wrapped into ±180, so no input can place a point
    /// outside the rectangle it is drawn into.
    static func unitPoint(latitude: Double, longitude: Double) -> CGPoint {
        let lat = min(max(latitude, -90), 90)
        let lon = wrapLongitude(longitude)
        return CGPoint(x: (lon + 180) / 360,
                       y: (90 - lat) / 180)
    }

    /// Longitude wrapped into [−180, 180], leaving **both** ends alone.
    ///
    /// Only values strictly outside the range move. −180 and +180 are the same meridian but the
    /// opposite edges of an equirectangular map, and both are real places to draw: a coastline ring
    /// that touches the dateline (Antarctica does) needs its −180 points on the left edge, while a
    /// meridian solved as +180 belongs on the right. Collapsing either onto the other drags a
    /// stroke across the whole map.
    static func wrapLongitude(_ lon: Double) -> Double {
        var l = lon.truncatingRemainder(dividingBy: 360)
        if l < -180 { l += 360 }
        if l > 180 { l -= 360 }
        return l
    }

    /// Splits a sequence of coordinates into drawable runs, breaking at the antimeridian.
    ///
    /// - Parameter points: `(latitude, longitude)` pairs in order along the line.
    /// - Returns: one array per continuous run. A line that never crosses returns a single run.
    static func segments(_ points: [(latitude: Double, longitude: Double)]) -> [[CGPoint]] {
        guard !points.isEmpty else { return [] }
        var runs: [[CGPoint]] = []
        var current: [CGPoint] = []
        var previousLon: Double?

        for p in points {
            let lon = wrapLongitude(p.longitude)
            if let prev = previousLon, abs(lon - prev) > 180 {
                // More than half a world between neighbours means the seam, not motion: the body
                // did not traverse the planet between two samples one degree of latitude apart.
                if current.count > 1 { runs.append(current) }
                current = []
            }
            current.append(unitPoint(latitude: p.latitude, longitude: lon))
            previousLon = lon
        }
        if current.count > 1 { runs.append(current) }
        return runs
    }

    /// Scales a unit point into a drawing rect.
    static func place(_ unit: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + unit.x * rect.width,
                y: rect.minY + unit.y * rect.height)
    }
}

/// Great-circle distance and which way a line lies — for the "near you" list.
enum GeoDistance {

    static let earthRadiusKm = 6371.0

    /// Haversine distance in kilometres.
    ///
    /// Haversine rather than the simpler spherical law of cosines: the latter loses precision for
    /// small separations, which is exactly the case that matters here — a line 12 km away is the
    /// interesting one, and it is where the naive formula is worst.
    static func kilometres(from a: (latitude: Double, longitude: Double),
                           to b: (latitude: Double, longitude: Double)) -> Double {
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
              + sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2)
        return 2 * earthRadiusKm * asin(min(1, sqrt(h)))
    }

    /// Whether the point sits east or west of an observer, accounting for the seam.
    ///
    /// Naively comparing longitudes puts a line at −179° "west" of an observer at +179°, when it is
    /// two degrees east of them.
    static func isEast(of observerLongitude: Double, point longitude: Double) -> Bool {
        MapProjection.wrapLongitude(longitude - observerLongitude) > 0
    }
}

extension CGSize {
    /// Component-wise addition, so a live gesture translation can be added to a stored offset
    /// without three lines of arithmetic at every call site.
    static func + (a: CGSize, b: CGSize) -> CGSize {
        CGSize(width: a.width + b.width, height: a.height + b.height)
    }
}
