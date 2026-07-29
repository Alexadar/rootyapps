import Foundation

/// An observer's place on Earth — the first geographic input this engine has ever needed
/// (houses and the angles are undefined without one).
///
/// Deliberately a plain value type: the Kit imports **no** CoreLocation and does no
/// geocoding or network lookup. Callers supply coordinates the user typed or picked from a
/// bundled list, so nothing about the user's whereabouts is ever collected or transmitted.
public struct GeoLocation: Hashable, Codable, Sendable {
    /// Degrees, **north positive**, clamped to [-90, 90].
    public let latitude: Double
    /// Degrees, **east positive**, wrapped to (-180, 180].
    public let longitude: Double
    /// Optional human label ("Kyiv", "37.77 N 122.42 W") — display only.
    public let name: String?

    public init(latitude: Double, longitude: Double, name: String? = nil) {
        self.latitude = min(90, max(-90, latitude))
        self.longitude = AstroMath.norm180(longitude)
        self.name = name
    }

    /// True inside the Arctic/Antarctic circles, where part of the ecliptic never rises or sets
    /// and the time-based systems (Placidus, Koch) break down.
    ///
    /// The real boundary is `90 − ε`, which drifts slightly with the epoch; this uses the J2000
    /// mean obliquity, so it can disagree with the engine by ~1e-4° for dates far from 2000.
    /// The systems themselves test against the obliquity of the date, not this constant.
    public var isPolar: Bool { abs(latitude) >= 90 - 23.4392911 }

    /// "50.45° N, 30.52° E"
    public var coordinateString: String {
        let ns = latitude >= 0 ? "N" : "S"
        let ew = longitude >= 0 ? "E" : "W"
        return String(format: "%.2f° %@, %.2f° %@", abs(latitude), ns, abs(longitude), ew)
    }
}
