import SwiftUI

@main
struct ephemeris_swiftApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 1010)
        .windowResizability(.contentSize)
        #endif
    }
}
