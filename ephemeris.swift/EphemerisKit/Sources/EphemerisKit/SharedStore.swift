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

    public func write(languageCode: String) { defaults.set(languageCode, forKey: Key.language) }
    public func write(houseSystem: HouseSystem) {
        defaults.set(houseSystem.rawValue, forKey: Key.houseSystem)
    }
}
