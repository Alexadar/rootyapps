import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct indoxtext_swiftApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 600, height: 500)
        .windowResizability(.contentSize)
        #endif
    }
}

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: TransparentWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Close default window
        NSApplication.shared.windows.first?.close()

        // Create transparent window with SwiftUI content
        windowController = TransparentWindowController(
            rootView: ContentView(),
            width: 600,
            height: 500
        )
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
#endif
