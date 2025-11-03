import SwiftUI
#if !os(macOS)
import UIKit
#else
import AppKit
#endif

#if !os(macOS)
/// AppDelegate used to enforce supported interface orientations (lock to landscape on mobile).
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return [.landscapeLeft, .landscapeRight]
    }
}
#else
/// AppDelegate for macOS to handle app termination with audio fade out
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        // Fade out audio before app terminates
        let semaphore = DispatchSemaphore(value: 0)
        AudioManager.shared.fadeOut(duration: 0.2) {
            semaphore.signal()
        }
        // Wait up to 0.3s for fade to complete
        _ = semaphore.wait(timeout: .now() + 0.3)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
#endif

@main
struct monstro_clientApp: App {
    #if !os(macOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Request device orientation to landscape at launch.
        DispatchQueue.main.async {
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeLeft.rawValue, forKey: "orientation")
        }
    }
    #else
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    init() {}
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    #if !os(macOS)
                    // Ensure orientation is set when the view appears.
                    UIDevice.current.setValue(UIInterfaceOrientation.landscapeLeft.rawValue, forKey: "orientation")
                    #endif
                }
        }
        #if os(macOS)
        .commands {
            // Handle Cmd+Q quit
            CommandGroup(replacing: .appTermination) {
                Button("Quit") {
                    AudioManager.shared.fadeOut(duration: 0.2) {
                        NSApplication.shared.terminate(nil)
                    }
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
        #endif
    }
}
