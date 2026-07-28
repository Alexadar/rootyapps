import SwiftUI

/// Marine Nav for Apple Watch.
///
/// STRUCTURAL v0.1 — deliberately unstyled, exactly as the phone app began. The visual
/// language (four appearance modes, red-shift, glanceable type ramp, complications) is
/// being designed separately and lands as `watch_guidelines/`; this file and its siblings
/// exist so that pass has a working, correctly-wired app to restyle rather than a mock.
///
/// It is a COMPANION app (embedded in the iOS app, same purchase) that nonetheless declares
/// `WKRunsIndependentlyOfCompanionApp` — so it must be fully usable with no iPhone nearby.
/// That is why the station catalogue is compiled in and nothing here reaches for the phone.
@main
struct MarineNavWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchTidesView()
        }
    }
}
