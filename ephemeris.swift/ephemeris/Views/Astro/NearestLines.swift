import Foundation
import EphemerisKit

/// "Which lines are near me" — the question a user actually asks of an astrocartography map.
///
/// The map answers *where*; this answers *how far*, which is what makes the screen usable without
/// pinching around looking for something. Pure, so the distances can be checked against known
/// geography without rendering anything.
enum NearestLines {

    /// One line's relationship to an observer.
    struct Proximity: Identifiable, Hashable {
        public let body: CelestialBody
        public let angle: AstroCartoAngle
        /// Nil when the line does not exist at all — see `absent`.
        public let kilometres: Double?
        public let isEast: Bool

        /// The line exists nowhere: the body is circumpolar at these latitudes, so it never touches
        /// the horizon and no AC or DC line can be drawn.
        ///
        /// ⚠️ This is a **real answer**, not a missing value. Clipping such a line to the edge of
        /// the map — the tempting fix — draws a boundary that does not exist and puts it somewhere
        /// a user could move to.
        public var absent: Bool { kilometres == nil }

        public var id: String { "\(body.rawValue)-\(angle.rawValue)" }
    }

    /// Every line ranked by distance from `observer`, absent ones last.
    ///
    /// Distance is measured to the **nearest sampled point** of the line. The Kit samples one point
    /// per degree of latitude by default, so the answer is good to a few tens of kilometres — far
    /// finer than the claim the feature makes ("you are near your Venus AC"), and it is not
    /// presented more precisely than that.
    static func ranked(_ lines: [AstroCartoLine],
                       observer: GeoLocation,
                       limit: Int = 12) -> [Proximity] {
        let here = (latitude: observer.latitude, longitude: observer.longitude)

        let all = lines.map { line -> Proximity in
            guard !line.isEmpty else {
                return Proximity(body: line.body, angle: line.angle, kilometres: nil, isEast: false)
            }
            var best = Double.infinity
            var bestLon = observer.longitude
            for p in line.points {
                let d = GeoDistance.kilometres(from: here, to: (p.latitude, p.longitude))
                if d < best { best = d; bestLon = p.longitude }
            }
            return Proximity(body: line.body, angle: line.angle, kilometres: best,
                             isEast: GeoDistance.isEast(of: observer.longitude, point: bestLon))
        }

        let present = all.filter { !$0.absent }.sorted { ($0.kilometres ?? 0) < ($1.kilometres ?? 0) }
        let missing = all.filter(\.absent)
        return Array((present + missing).prefix(limit))
    }
}
