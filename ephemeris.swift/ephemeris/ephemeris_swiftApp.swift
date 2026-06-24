import SwiftUI

@main
struct ephemeris_swiftApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 980, height: 720)
        .windowResizability(.contentSize)
        #endif
    }
}
