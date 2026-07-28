// Ported from calculators/marine-navigation/intercept.swift/InterceptKit (oracle-first harvest, 2026-07-08).
// Sensor/Optic (astro-camera models, unused in marine nav) dropped in the harvest.
import Foundation

/// Observer location. Longitude east-positive, degrees.
public struct GeoLocation: Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Equatorial + ecliptic coordinates of a body, degrees (RA/Dec/lon/lat) and distance (Earth radii for Moon, AU for Sun-scale is unused).
public struct SkyPosition: Sendable, Equatable {
    public var rightAscension: Double   // degrees [0,360)
    public var declination: Double      // degrees [-90,90]
    public var eclipticLongitude: Double
    public var eclipticLatitude: Double
    public init(rightAscension: Double, declination: Double, eclipticLongitude: Double, eclipticLatitude: Double) {
        self.rightAscension = rightAscension
        self.declination = declination
        self.eclipticLongitude = eclipticLongitude
        self.eclipticLatitude = eclipticLatitude
    }
}

/// Horizontal coordinates, degrees. Azimuth measured from North, clockwise.
public struct Horizontal: Sendable, Equatable {
    public var altitude: Double
    public var azimuth: Double
    public init(altitude: Double, azimuth: Double) {
        self.altitude = altitude
        self.azimuth = azimuth
    }
}

/// A rise/set (or twilight) pair for a day. nil when the body never crosses the altitude.
public struct RiseSet: Sendable, Equatable {
    public var rise: Date?
    public var set: Date?
    public var alwaysUp: Bool
    public var alwaysDown: Bool
    public init(rise: Date?, set: Date?, alwaysUp: Bool, alwaysDown: Bool) {
        self.rise = rise; self.set = set; self.alwaysUp = alwaysUp; self.alwaysDown = alwaysDown
    }
}

