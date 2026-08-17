import Foundation

/// Why an elevation could not be used.
public enum ElevationError: Error, Equatable, Sendable, CustomStringConvertible {
    /// Outside the published validity range of the standard-atmosphere equation.
    case outOfRange(metres: Double)

    public var description: String {
        switch self {
        case .outOfRange(let z):
            return "elevation \(z) m is outside the standard atmosphere's valid range "
                 + "\(Elevation.validRange) m"
        }
    }
}

/// Site elevation, and the barometric pressure that goes with it.
///
/// Altitude is a first-class input in this app, never a buried setting: at Denver the air-side
/// constants are 18 % off their sea-level values, and a tool that quietly assumes sea level is
/// wrong by that much on every screen.
///
/// ## Source
///
/// **ASHRAE Fundamentals Ch. 1, eq. 3** — the standard atmosphere:
/// `p = 101.325 (1 − 2.25577 × 10⁻⁵ Z)^5.2559` kPa, with `Z` in metres. Published validity
/// −5,000 to 11,000 m. The companion temperature profile (eq. 4) is `t = 15 − 0.0065 Z` °C.
///
/// This is a *standard* atmosphere, not today's weather: it gives the pressure a site sits at on
/// average, which is what equipment is selected against. A barometer reading corrected to sea
/// level — the number a weather app shows — is not this and must not be typed in here.
public struct Elevation: Equatable, Sendable, Codable, Comparable, Hashable {

    /// Published validity range of the standard-atmosphere equation, metres.
    public static let validRange = -5_000.0 ... 11_000.0

    /// Standard sea-level pressure, Pa.
    public static let seaLevelPressure = 101_325.0
    /// Standard sea-level temperature, °C.
    public static let seaLevelTemperature = 15.0
    /// Temperature lapse rate of the standard atmosphere, °C per metre.
    public static let lapseRate = 0.0065

    /// Height above sea level, metres.
    public let metres: Double

    public init(metres: Double) throws {
        guard metres.isFinite, Self.validRange.contains(metres) else {
            throw ElevationError.outOfRange(metres: metres)
        }
        self.metres = metres
    }

    /// Height above sea level in feet — the unit the trade works in.
    public init(feet: Double) throws {
        try self.init(metres: feet * 0.3048)
    }

    public var feet: Double { metres / 0.3048 }

    public static func < (lhs: Elevation, rhs: Elevation) -> Bool { lhs.metres < rhs.metres }

    // MARK: - Standard atmosphere

    /// Local barometric pressure, Pa.
    public var barometricPressure: Double {
        Self.seaLevelPressure * pow(1 - 2.25577e-5 * metres, 5.2559)
    }

    /// Standard-atmosphere dry-bulb temperature at this elevation, °C.
    ///
    /// A sensible default for an empty field, not a claim about the weather.
    public var standardTemperature: Double {
        Self.seaLevelTemperature - Self.lapseRate * metres
    }

    /// Local pressure as a fraction of sea level.
    ///
    /// At a fixed temperature this is also the air-density ratio, which is why the trade's
    /// per-CFM constants scale by it. It is **not** the density ratio when the temperature also
    /// differs — for that, take the density from an actual solved air state.
    public var pressureRatio: Double { barometricPressure / Self.seaLevelPressure }

    // MARK: - Named sites

    /// Sea level.
    public static let seaLevel = Elevation(uncheckedMetres: 0)
    /// Denver, 5,280 ft — the standard "does this tool handle altitude" test case.
    public static let denver = Elevation(uncheckedMetres: 5280 * 0.3048)
    /// Mexico City, 7,350 ft.
    public static let mexicoCity = Elevation(uncheckedMetres: 7350 * 0.3048)

    /// For the compile-time constants above, whose values are known to be in range.
    private init(uncheckedMetres: Double) { self.metres = uncheckedMetres }
}
