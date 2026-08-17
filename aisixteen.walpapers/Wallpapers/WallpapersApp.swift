import SwiftUI

@main
struct WallpapersApp: App {
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        #if os(macOS)
        // The window is a design object with its own proportions, not a stretched phone screen.
        // 1140 × 700 is the bundle's reference size.
        .defaultSize(width: 1140, height: 700)
        .windowResizability(.contentMinSize)
        .commands {
            // The Mac's About door. It gets the real menu-bar item rather than the `⋯` the touch
            // shells use — a Mac user looks in the app menu, and putting it anywhere else would be
            // a phone idiom wearing a desktop coat.
            CommandGroup(replacing: .appInfo) {
                Button("About AISixteen Wallpapers") { openWindow(id: AboutWindow.id) }
            }
        }
        #endif

        #if os(macOS)
        Window("About AISixteen Wallpapers", id: AboutWindow.id) {
            // No `settings` and no `location`: this scene lives outside `RootView`'s state, so it
            // resolves the library location itself. Advanced stays where it is on Mac.
            AboutView(location: nil, settings: nil)
                .background(MacPaperBackground())
        }
        .defaultSize(width: 460, height: 560)
        .windowResizability(.contentSize)
        #endif
    }
}

enum AboutWindow {
    static let id = "about"
}
