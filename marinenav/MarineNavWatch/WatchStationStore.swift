import SwiftUI
import TidesKit

// ─────────────────────────────────────────────────────────────────────────────
// Extracted from WatchStationPickerView.swift on adoption.
//
// The widget extension needs the STORE but not the picker. Leaving them in one file
// forced the extension to compile a SwiftUI View that pulls in CoreLocation and
// GeodesyKit, which failed to link (Vincenty.inverse undefined) and would have bloated
// a process that only ever reads two strings.
// ─────────────────────────────────────────────────────────────────────────────

/// Persists the chosen station and unit. No pairing-time transfer from the phone:
/// the watch app runs independently, so it owns its own selection.
///
/// ⚠ ADOPTION FIX — the store MUST live in the App Group suite, not standard
/// `UserDefaults`. `MarineNavComplications` reads this from the **widget extension**,
/// which is a separate process with its own container: against the standard suite it
/// can never see `watch.tideStation`, so every complication family would render its
/// "no station chosen" branch forever — the one path the design wrote as an edge case
/// would become the only path. Sight marks are unaffected; they are a JSON file in the
/// watch's own container by design.
@MainActor
final class WatchStationStore: ObservableObject {
    static let shared = WatchStationStore()

    /// Shared by the watch app and its widget extension. Falls back to `.standard` only
    /// so a missing entitlement degrades to "complication shows no station" rather than
    /// a crash on launch.
    static let suiteName = "group.oleksandr.aisixteen.marinenav"
    nonisolated static let defaults: UserDefaults =
        UserDefaults(suiteName: suiteName) ?? .standard

    @AppStorage("watch.tideStation", store: WatchStationStore.defaults)
    var selectedTideStationID: String = StationCatalog.tideStations.first!.id
    @AppStorage("watch.currentStation", store: WatchStationStore.defaults)
    var selectedCurrentStationKey: String = StationCatalog.currentStations.first!.stationKey
    @AppStorage("watch.unit", store: WatchStationStore.defaults)
    private var unitRaw: String = "feet"
    /// Most-recent-first, capped. The only "favourites" mechanism on the watch —
    /// a starring UI is not worth the taps at this screen size.
    @AppStorage("watch.recentStations", store: WatchStationStore.defaults)
    private var recentsRaw: String = ""

    var unit: TideUnit {
        get { unitRaw == "meters" ? .meters : .feet }
        set { unitRaw = newValue == .meters ? "meters" : "feet" }
    }

    // MARK: Nonisolated reads for the widget extension
    //
    // `TimelineProvider.getTimeline` is not main-actor isolated, so it cannot touch
    // `shared`. It does not need to: the backing store is just the App Group suite, and
    // these are plain reads of the same keys `@AppStorage` writes. Keeping them here — beside
    // the writers, using the same key strings — is what stops the two drifting apart.

    nonisolated static var storedTideStationID: String {
        defaults.string(forKey: "watch.tideStation") ?? StationCatalog.tideStations.first!.id
    }

    nonisolated static var storedUnit: TideUnit {
        defaults.string(forKey: "watch.unit") == "meters" ? .meters : .feet
    }

    nonisolated static var storedCurrentStationKey: String {
        defaults.string(forKey: "watch.currentStation")
            ?? StationCatalog.currentStations.first!.stationKey
    }

    var recents: [String] {
        recentsRaw.split(separator: ",").map(String.init)
    }

    func remember(_ id: String) {
        var list = recents.filter { $0 != id }
        list.insert(id, at: 0)
        recentsRaw = list.prefix(6).joined(separator: ",")
    }
}
