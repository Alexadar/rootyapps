import SwiftUI
#if !os(macOS)
import UIKit
#endif

#if !os(macOS)
/// AppDelegate used to enforce supported interface orientations (lock to landscape on mobile).
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return [.landscapeLeft, .landscapeRight]
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
    }
}
