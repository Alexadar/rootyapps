import SpriteKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Lifecycle & Background Handling
extension GameScene {

    // MARK: - Window / focus handling
#if os(macOS)
    @objc func windowDidResignKey(_ notification: Notification) {
        NSCursor.unhide()
        NSCursor.arrow.set()
    }
#endif

    // Background / foreground handlers to pause/resume rendering and avoid Metal submission from background.
    #if !os(macOS)
    @objc func appDidEnterBackground() {
        // Pause the SKView to stop metal work when app is backgrounded.
        self.view?.isPaused = true
    }

    @objc func appWillEnterForeground() {
        // Resume rendering when the app returns to foreground.
        self.view?.isPaused = false
    }
    #else
    @objc func appWillResignActive(_ notification: Notification) {
        self.view?.isPaused = true
    }

    @objc func appDidBecomeActive(_ notification: Notification) {
        self.view?.isPaused = false
    }
    #endif

    override func willMove(from view: SKView?) {
        if let v = view {
            super.willMove(from: v)
        } else {
            super.willMove(from: SKView())
        }
#if os(macOS)
        NSCursor.unhide()
        NSCursor.arrow.set()
        if let ta = trackingArea, let v = view {
            v.removeTrackingArea(ta)
            trackingArea = nil
        }
#endif
        NotificationCenter.default.removeObserver(self)
    }
}
