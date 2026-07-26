import SwiftUI

@main
struct KerfCalcApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 780)
        .windowResizability(.automatic)
        #endif
    }
}
