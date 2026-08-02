import SwiftUI

/// Kerf Calc on the wrist — a standalone companion carrying the six fastest tools.
/// `CrownFocus` lives at the root and is injected once; every crown-driven screen reads it so a
/// tapped Button/Toggle/Picker can hand the Digital Crown back to the field (see WatchComponents).
@main
struct KerfCalcWatchApp: App {
    @StateObject private var crownFocus = CrownFocus()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(crownFocus)
                .tint(KCW.signal)
                .preferredColorScheme(.dark)
        }
    }
}
