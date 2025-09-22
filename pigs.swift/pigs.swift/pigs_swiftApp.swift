import SwiftUI

@main
struct pigs_swiftApp: App {
    @StateObject private var gameEngine = GameEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(gameEngine)
            #if os(iOS)
                .statusBarHidden(true)
            #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 700)
        .windowResizability(.contentSize)
        #endif
    }
}
