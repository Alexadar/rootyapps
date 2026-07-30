import SwiftUI

/// TrueCourse on the wrist — a standalone companion carrying all 9 E6B calculators.
/// `CrownFocus` lives at the root and is injected once; every crown-driven screen reads it so a
/// tapped Button/Picker can hand the Digital Crown back to its field. `.tcTheme(.dark)` supplies the
/// glass-cockpit palette (the same tokens as the phone; Night is a one-line swap later).
@main
struct TrueCourseWatchApp: App {
    @StateObject private var crownFocus = CrownFocus()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(crownFocus)
                .tcTheme(.dark)
        }
    }
}
