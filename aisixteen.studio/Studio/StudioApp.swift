import SwiftUI

@main
struct StudioApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        #if os(macOS)
        // ⚠️ Not a `DocumentGroup`. A SwiftUI document app opens on an empty Open panel on the Mac,
        // which this repository has already had rejected under 2.1(a) — and it would be wrong here
        // anyway: the app's own library is the document, not a file the user picks first.
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        #endif
    }
}
