import Foundation

/// The App Group container, and the handful of preferences that have to survive a process
/// boundary.
///
/// Three processes need the same answers: the app, the widget/complication extension, and the
/// watch app. A widget extension has its own bundle and its own `UserDefaults.standard`, so
/// anything written with plain `@AppStorage` in the app is simply invisible to it — the
/// complication would render with defaults and look plausible while being wrong.
///
/// **App groups are per-device.** This container is shared between the app and its extensions on
/// *one* device. It does NOT reach the watch from the phone. Crossing that gap needs
/// WatchConnectivity; see `WatchBridge`. Getting this wrong is subtle: the phone writes a place,
/// the watch reads its own empty container, and the Ascendant silently has no observer.
public enum AppGroup {
    public static let identifier = "group.oleksandr.aisixteen.ephemeris"

    /// Falls back to `.standard` rather than crashing: a missing entitlement should degrade to
    /// "preferences don't cross processes", not take the app down at launch.
    public static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}

/// Typed access to everything shared across processes.
///
/// Deliberately small. Positions, aspects and cusps are NOT stored here — the engine recomputes
/// them in milliseconds on every device, so shipping a snapshot across would add a staleness bug
/// in exchange for nothing.
public struct SharedStore {
    public enum Key {
        /// Selected app language, or "" for "follow the system".
        public static let language = "appLanguage"
        /// Observer position. The Ascendant and house cusps are undefined without it — unlike
        /// planetary positions, which are geocentric and need no place at all.
        public static let latitude  = "observerLatitude"
        public static let longitude = "observerLongitude"
        public static let placeName = "observerPlaceName"
        /// House system raw value, so a complication showing a cusp matches the app.
        public static let houseSystem = "houseSystem"

        /// The default chart's birth instant and name, for the watch's Returns row.
        ///
        /// Two values and no more. The watch has `EphemerisKit`, so from a birth instant it can
        /// compute the natal longitudes and the next return itself — sending a chart's *results*
        /// would be a snapshot that goes stale the moment the return passes, and sending the whole
        /// chart file would put someone's birth record on a second device to save arithmetic that
        /// takes milliseconds.
        ///
        /// Nothing is sent for a chart with no birth time: a return needs an exact moment, so the
        /// row would have nothing honest to show.
        public static let defaultChartInstant = "defaultChartInstant"
        public static let defaultChartName = "defaultChartName"
    }

    private let defaults: UserDefaults
    public init(defaults: UserDefaults = AppGroup.defaults) { self.defaults = defaults }

    public var languageCode: String? { defaults.string(forKey: Key.language) }

    /// Nil when no place has been set — the caller must handle that, not substitute a default.
    /// A guessed location produces a confidently wrong Ascendant, which is worse than showing
    /// nothing, because nothing about the output looks wrong.
    public var location: GeoLocation? {
        guard defaults.object(forKey: Key.latitude) != nil,
              defaults.object(forKey: Key.longitude) != nil else { return nil }
        return GeoLocation(latitude: defaults.double(forKey: Key.latitude),
                           longitude: defaults.double(forKey: Key.longitude),
                           name: defaults.string(forKey: Key.placeName))
    }

    public var houseSystem: HouseSystem {
        HouseSystem(rawValue: defaults.string(forKey: Key.houseSystem) ?? "") ?? .placidus
    }

    /// The chart the watch should show a return for, or nil when none is set.
    ///
    /// Nil is a real state and not a failure: with no default chart the watch simply has no
    /// Returns row, which is the correct outcome rather than a placeholder inviting a tap that
    /// leads nowhere.
    public var defaultChart: (instant: Date, name: String)? {
        guard let seconds = defaults.object(forKey: Key.defaultChartInstant) as? Double,
              let name = defaults.string(forKey: Key.defaultChartName), !name.isEmpty
        else { return nil }
        return (Date(timeIntervalSince1970: seconds), name)
    }

    // MARK: Writing — the app is the only writer; extensions read.

    public func write(location: GeoLocation?) {
        if let location {
            defaults.set(location.latitude,  forKey: Key.latitude)
            defaults.set(location.longitude, forKey: Key.longitude)
            defaults.set(location.name,      forKey: Key.placeName)
        } else {
            [Key.latitude, Key.longitude, Key.placeName].forEach(defaults.removeObject(forKey:))
        }
    }

    /// Passing nil clears it — which is what must happen when the user unsets the default chart or
    /// deletes it, or the watch keeps showing a return for a chart that no longer exists.
    public func write(defaultChart: (instant: Date, name: String)?) {
        if let defaultChart {
            defaults.set(defaultChart.instant.timeIntervalSince1970, forKey: Key.defaultChartInstant)
            defaults.set(defaultChart.name, forKey: Key.defaultChartName)
        } else {
            [Key.defaultChartInstant, Key.defaultChartName].forEach(defaults.removeObject(forKey:))
        }
    }

    public func write(languageCode: String) { defaults.set(languageCode, forKey: Key.language) }
    public func write(houseSystem: HouseSystem) {
        defaults.set(houseSystem.rawValue, forKey: Key.houseSystem)
    }
}
