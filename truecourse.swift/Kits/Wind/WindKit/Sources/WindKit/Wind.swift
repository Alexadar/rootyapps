import Foundation

/// Wind-triangle math for the E6B flight computer.
///
/// Directions are true degrees (0–360, 0 = north, clockwise). Wind direction is the
/// meteorological convention — the direction the wind blows **from**. Speeds are knots.
public enum Wind {

    /// Full wind-triangle solution: given the desired course (track over the ground),
    /// true airspeed and the wind, find the heading to fly, the resulting groundspeed
    /// and the wind-correction angle (crab).
    ///
    /// - Returns: `heading` = true heading to fly (deg), `groundspeed` (kt),
    ///   `wca` = wind-correction angle (deg, +right / into a wind from the right).
    ///   Returns `nil` if the crosswind exceeds TAS (course cannot be held).
    public static func solution(courseDeg: Double,
                                tasKt: Double,
                                windDirDeg: Double,
                                windSpeedKt: Double) -> (headingDeg: Double, gsKt: Double, wcaDeg: Double)? {
        guard tasKt > 0 else { return nil }
        let d = (windDirDeg - courseDeg) * .pi / 180
        let swc = (windSpeedKt / tasKt) * sin(d)          // sine of the wind-correction angle
        guard abs(swc) <= 1 else { return nil }           // wind too strong to hold course
        let wca = asin(swc) * 180 / .pi
        let gs = tasKt * sqrt(1 - swc * swc) - windSpeedKt * cos(d)
        return (normalizeDeg(courseDeg + wca), gs, wca)
    }

    /// Runway wind components. `headwind` is positive for a headwind (negative = tailwind);
    /// `crosswind` is positive for wind from the right of the runway heading.
    public static func components(runwayHeadingDeg: Double,
                                  windDirDeg: Double,
                                  windSpeedKt: Double) -> (headwindKt: Double, crosswindKt: Double) {
        let a = (windDirDeg - runwayHeadingDeg) * .pi / 180
        return (windSpeedKt * cos(a), windSpeedKt * sin(a))
    }

    /// Derive the wind (direction it blows **from**, and speed) from a measured
    /// course/track, heading actually flown, true airspeed and groundspeed.
    public static func derive(courseDeg: Double,
                              headingDeg: Double,
                              tasKt: Double,
                              gsKt: Double) -> (windDirDeg: Double, windSpeedKt: Double) {
        let h = headingDeg * .pi / 180
        let c = courseDeg * .pi / 180
        // Air vector (heading, TAS) and ground vector (track, GS) in east/north components.
        let airX = tasKt * sin(h), airY = tasKt * cos(h)
        let gndX = gsKt * sin(c),  gndY = gsKt * cos(c)
        // Wind vector = ground − air (the direction the air is moving toward).
        let wx = gndX - airX, wy = gndY - airY
        let speed = (wx * wx + wy * wy).squareRoot()
        let toDeg = normalizeDeg(atan2(wx, wy) * 180 / .pi)
        return (normalizeDeg(toDeg + 180), speed)          // convert "toward" → "from"
    }

    private static func normalizeDeg(_ deg: Double) -> Double {
        let r = deg.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    // MARK: - Diagram geometry (drives the wind-triangle drawing)

    /// A 2-D vector in the diagram's screen convention: +x = east/right, +y = down,
    /// bearing 0° (north) points straight up. This is exactly the mapping the
    /// `WindTriangleView` canvas uses, extracted here so the drawing can be verified.
    public struct Vec2: Sendable, Equatable {
        public let x: Double
        public let y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }

        /// Length (in the same units as the input magnitudes, at unit scale).
        public var magnitude: Double { (x * x + y * y).squareRoot() }
        /// The compass bearing this vector points toward (deg true, 0…360).
        public var bearingDeg: Double { normalizeDeg(atan2(x, -y) * 180 / .pi) }
    }

    /// The three vectors of the wind triangle at unit scale, from a common origin:
    /// `air` (heading/TAS), `track` (course/GS), and `wind` = `track − air` (the vector the
    /// wind pushes the aircraft along, i.e. blowing **toward** `windFrom + 180`).
    /// By construction `air + wind == track`, so the drawing is a closed, faithful triangle.
    public struct Triangle: Sendable, Equatable {
        public let air: Vec2
        public let track: Vec2
        public let wind: Vec2
    }

    /// Screen-space vectors for the diagram. `headingDeg`/`gsKt` come from `solution(...)`.
    public static func triangle(courseDeg: Double, tasKt: Double,
                                headingDeg: Double, gsKt: Double) -> Triangle {
        func v(_ bearing: Double, _ mag: Double) -> Vec2 {
            let r = bearing * .pi / 180
            return Vec2(x: sin(r) * mag, y: -cos(r) * mag)
        }
        let air = v(headingDeg, tasKt)
        let track = v(courseDeg, gsKt)
        return Triangle(air: air, track: track, wind: Vec2(x: track.x - air.x, y: track.y - air.y))
    }
}
