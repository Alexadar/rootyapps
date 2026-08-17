import Foundation
import Observation
import AltitudeKit
import UnitsKit

// DesignShared is compiled into the watch target as well as the phone, so it may only import the
// Kits the watch links: units, altitude and the psychrometric solver. Duct and pipe types stay on
// the phone side of the line — which is why the velocity limit below is a plain number here and is
// interpreted by the duct tool.

/// Small, boring, reliable persistence.
///
/// Everything this app remembers is a handful of numbers, so it goes in `UserDefaults` as JSON.
/// No store, no migration story, no database to corrupt. If a value cannot be decoded — because a
/// build changed a model's shape — the app starts that tool fresh rather than refusing to launch.
public enum Persistence {

    public static var defaults: UserDefaults = .standard

    /// Wipe everything this app remembers.
    ///
    /// A UI test that inherits the previous test's persisted state passes for the wrong reason —
    /// and, once, failed for one. But this is scaffolding, so it goes through
    /// ``LaunchOverride`` and **does not exist in a Release build**: an earlier version read a
    /// launch argument straight out of `UserDefaults`, which shipped a switch that could wipe a
    /// customer's saved work from outside the app (`open --env` on macOS). See uitests.md §4b.
    public static func resetIfRequested() {
        guard LaunchOverride.flag("AIRCORE_RESET") else { return }
        // AppKit's own autosaved window geometry counts as saved state too.
        //
        // SwiftUI writes "NSWindow Frame <view-hierarchy-key>" and the matching split-view
        // fractions into the app's OWN preferences domain — which `-ApplePersistenceIgnoreState
        // YES` does not touch, since that flag governs the system's window restoration, not
        // NSWindow's frame autosave. A restored frame beats `.defaultSize` outright, so a run that
        // asked for a different window size silently got the last one instead, and a suite that
        // believed it was launching clean was inheriting whatever the previous run left.
        //
        // The prefixes are AppKit's, not ours, so they are matched rather than named: the key
        // embeds the full modifier chain of the root view and changes every time a modifier is
        // added anywhere above it.
        let prefixes = ["AirCore.", "NSWindow Frame ", "NSSplitView Subview Frames "]
        for key in defaults.dictionaryRepresentation().keys
        where prefixes.contains(where: key.hasPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    public static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    public static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// The settings that apply to every tool at once.
///
/// ## Altitude is not a preference
///
/// Elevation lives here because it applies to every screen, not because it is a setting to be
/// buried in one. Every tool shows the current elevation in its header and every tool's numbers
/// are computed at it. Most competing tools assume sea level silently, and are wrong by 18 % in
/// Denver as a result.
@Observable
public final class AppSettings {

    private static let key = "AirCore.settings"

    public var unitSystem: UnitSystem { didSet { save() } }
    /// Site elevation in metres. Stored in SI like everything else.
    public var elevationMetres: Double { didSet { save() } }
    /// The user's own duct velocity ceiling, m/s, defaulting to the 1,200 fpm rule of thumb.
    ///
    /// > Note: This is the user's number, not a code limit. Per-application velocity tables are
    /// > published in licensed documents and none is embedded anywhere in this app.
    public var ductVelocityLimit: Double { didSet { save() } }
    /// Whether the water side is a heating loop — hot water erodes copper at a lower velocity, so
    /// it gets the lower ceiling.
    public var waterIsHot: Bool { didSet { save() } }
    /// Tools the user has opened, most recent first.
    public var recentTools: [Tool] { didSet { save() } }

    /// 1,200 fpm in m/s.
    public static let defaultDuctVelocityLimit = 1200 * 0.3048 / 60

    public var elevation: Elevation {
        (try? Elevation(metres: elevationMetres)) ?? .seaLevel
    }

    /// Barometric pressure at the site, Pa — the input almost every Kit takes.
    public var pressure: Double { elevation.barometricPressure }

    public init(unitSystem: UnitSystem = .ip,
                elevationMetres: Double = 0,
                ductVelocityLimit: Double = AppSettings.defaultDuctVelocityLimit,
                waterIsHot: Bool = false,
                recentTools: [Tool] = []) {
        self.unitSystem = unitSystem
        self.elevationMetres = elevationMetres
        self.ductVelocityLimit = ductVelocityLimit
        self.waterIsHot = waterIsHot
        self.recentTools = recentTools
    }

    /// Note the user opened a tool. Most recent first, no duplicates, four remembered — enough to
    /// put the tools of the job one tap from launch without turning the home screen into a list of
    /// everything.
    public func noteOpened(_ tool: Tool) {
        var updated = recentTools.filter { $0 != tool }
        updated.insert(tool, at: 0)
        recentTools = Array(updated.prefix(4))
    }

    // MARK: - Persistence

    private struct Stored: Codable {
        var unitSystem: String
        var elevationMetres: Double
        var ductVelocityLimit: Double
        var waterIsHot: Bool
        var recentTools: [Tool]
    }

    // Property observers do not fire during `init`, so loading cannot trigger a save of what was
    // just loaded, and no re-entrancy guard is needed here.
    private func save() {
        Persistence.save(Stored(unitSystem: unitSystem.rawValue,
                                elevationMetres: elevationMetres,
                                ductVelocityLimit: ductVelocityLimit,
                                waterIsHot: waterIsHot,
                                recentTools: recentTools),
                         key: Self.key)
    }

    /// Load what was there, or start clean.
    public static func loaded() -> AppSettings {
        guard let stored = Persistence.load(Stored.self, key: key) else { return AppSettings() }
        let settings = AppSettings(
            unitSystem: UnitSystem(rawValue: stored.unitSystem) ?? .ip,
            elevationMetres: stored.elevationMetres,
            ductVelocityLimit: stored.ductVelocityLimit,
            waterIsHot: stored.waterIsHot,
            recentTools: stored.recentTools)
        return settings
    }
}
