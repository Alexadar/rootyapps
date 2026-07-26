import SwiftUI

@main
struct OverToneLabApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 820)
        .windowResizability(.automatic)
        #endif
    }
}
