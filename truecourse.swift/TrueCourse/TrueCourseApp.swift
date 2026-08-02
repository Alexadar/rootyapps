import SwiftUI

@main
struct TrueCourseApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
            #if os(macOS)
                .frame(minWidth: 720, minHeight: 520)   // §7: keep content usable when resized
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 820)
        .windowResizability(.contentSize)
        #endif
    }
}
