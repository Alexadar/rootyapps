import Foundation

/// The app group shared by the app, widgets, watch app, and background task.
public enum AppGroup {
    public static let id = "group.oleksandr.aisixteen.eartharound"
    /// Falls back to standard defaults where the group isn't provisioned (unit tests).
    public static let defaults = UserDefaults(suiteName: id) ?? .standard
}

/// One source of truth in the app group: last-good snapshot + refresh time, theme
/// choice, alert preferences, and the alert-dedupe state. Every process writes
/// through here; nobody re-fetches what another process already has.
public struct SharedStore {
    public enum Key {
        public static let snapshot = "shared.snapshot"
        public static let lastRefresh = "shared.lastRefresh"
        public static let theme = "sw.theme"
        public static let mode = "sw.mode"
        public static let alertState = "alerts.state"
        public static let alertsEnabled = "alerts.enabled"
        public static let alertStorms = "alerts.storms"
        public static let alertStormThreshold = "alerts.stormThreshold"
        public static let alertFlares = "alerts.flares"
        public static let alertAurora = "alerts.aurora"
        public static let alertAuroraThreshold = "alerts.auroraThreshold"
    }

    private let defaults: UserDefaults
    public init(defaults: UserDefaults = AppGroup.defaults) { self.defaults = defaults }

    // MARK: Snapshot

    public func save(_ snapshot: SpaceWeatherSnapshot, at date: Date) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Key.snapshot)
        defaults.set(date, forKey: Key.lastRefresh)
    }

    public func load() -> (snapshot: SpaceWeatherSnapshot, at: Date)? {
        guard let data = defaults.data(forKey: Key.snapshot),
              let snapshot = try? JSONDecoder().decode(SpaceWeatherSnapshot.self, from: data),
              let at = defaults.object(forKey: Key.lastRefresh) as? Date else { return nil }
        return (snapshot, at)
    }

    // MARK: Theme (raw value of the app's SWThemeChoice)

    public var themeRaw: String? {
        get { defaults.string(forKey: Key.theme) }
        nonmutating set { defaults.set(newValue, forKey: Key.theme) }
    }

    // MARK: Detail mode (raw value of the app's SWMode)

    public var modeRaw: String? {
        get { defaults.string(forKey: Key.mode) }
        nonmutating set { defaults.set(newValue, forKey: Key.mode) }
    }

    // MARK: Alerts

    public var alertPrefs: AlertPrefs {
        get {
            AlertPrefs(
                enabled: defaults.bool(forKey: Key.alertsEnabled),
                storms: defaults.object(forKey: Key.alertStorms) as? Bool ?? true,
                stormThreshold: defaults.object(forKey: Key.alertStormThreshold) as? Int ?? 1,
                flares: defaults.object(forKey: Key.alertFlares) as? Bool ?? true,
                aurora: defaults.object(forKey: Key.alertAurora) as? Bool ?? true,
                auroraThreshold: defaults.object(forKey: Key.alertAuroraThreshold) as? Int ?? 50)
        }
        nonmutating set {
            defaults.set(newValue.enabled, forKey: Key.alertsEnabled)
            defaults.set(newValue.storms, forKey: Key.alertStorms)
            defaults.set(newValue.stormThreshold, forKey: Key.alertStormThreshold)
            defaults.set(newValue.flares, forKey: Key.alertFlares)
            defaults.set(newValue.aurora, forKey: Key.alertAurora)
            defaults.set(newValue.auroraThreshold, forKey: Key.alertAuroraThreshold)
        }
    }

    public var alertState: AlertDedupeState {
        get {
            guard let data = defaults.data(forKey: Key.alertState),
                  let state = try? JSONDecoder().decode(AlertDedupeState.self, from: data)
            else { return AlertDedupeState() }
            return state
        }
        nonmutating set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.alertState)
        }
    }
}
