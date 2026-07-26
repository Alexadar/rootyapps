import Foundation
import SpaceWeatherFeed
import WidgetKit
#if os(iOS)
import BackgroundTasks
#endif

/// Opportunistic background refresh (iOS): fetch → persist to the app group →
/// evaluate alerts → reload widget timelines → book the next slot. The system
/// decides when it actually runs (typically a few times a day) — the widget
/// provider and foreground refresh cover the gaps, and Settings says so honestly.
/// macOS has no BGTaskScheduler for sandboxed GUI apps; there the foreground
/// auto-refresh timer feeds the same AlertNotifier path.
enum BackgroundUpdateManager {
    static let taskID = "oleksandr.aisixteen.eartharound.refresh"

    #if os(iOS)
    /// Must run before the app finishes launching (App.init).
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let work = Task { @MainActor in
                schedule()
                let store = SpaceWeatherStore()
                await store.refresh()
                let ok = !store.isOffline
                if ok {
                    AlertNotifier.handle(store.snapshot)
                    WidgetCenter.shared.reloadAllTimelines()
                }
                refresh.setTaskCompleted(success: ok)
            }
            refresh.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
    #else
    static func register() {}
    static func schedule() {}
    #endif
}
