//
//  MacOSContentView.swift
//  indoxtext.swift
//
//  macOS-specific content view with liquid glass window
//

import SwiftUI

#if os(macOS)
import AppKit

struct MacOSContentView: View {
    @StateObject private var navigationCoordinator = NavigationCoordinator()
    @StateObject private var summarizerState = SummarizerStateManager()

    var body: some View {
        NavigationStack(path: $navigationCoordinator.navigationPath) {
            MacOSHomeView()
                .navigationDestination(for: NavigationDestination.self) { destination in
                    switch destination {
                    case .home:
                        MacOSHomeView()
                    case .fromText:
                        FromTextView()
                    case .fromFile:
                        FromFileView()
                    case .result:
                        ResultView()
                    }
                }
        }
        .environmentObject(navigationCoordinator)
        .environmentObject(summarizerState)
    }
}

// MARK: - Transparent Window Classes for Liquid Glass

class TransparentWindow: NSWindow {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        // Add fullSizeContentView to style mask
        var styleMask = style
        styleMask.insert(.fullSizeContentView)

        super.init(contentRect: contentRect, styleMask: styleMask, backing: backingStoreType, defer: flag)

        self.isOpaque = false
        self.backgroundColor = .clear
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden

        // Add single unified visual effect view as background
        let visualEffectView = NSVisualEffectView(frame: contentRect)
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.material = .hudWindow
        visualEffectView.state = .active
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.wantsLayer = true

        // Add rounded corners and border for glass effect
        visualEffectView.layer?.cornerRadius = 12
        visualEffectView.layer?.borderWidth = 1
        visualEffectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        visualEffectView.layer?.masksToBounds = true

        // Add subtle shadow for depth
        self.hasShadow = true

        self.contentView = visualEffectView
    }
}

class TransparentWindowController: NSWindowController {
    convenience init<Content: View>(rootView: Content, width: CGFloat, height: CGFloat) {
        let window = TransparentWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        self.init(window: window)

        // Create hosting view for SwiftUI content
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.autoresizingMask = [.width, .height]

        // Add hosting view to the visual effect view
        if let visualEffectView = window.contentView as? NSVisualEffectView {
            visualEffectView.addSubview(hostingView)
            hostingView.frame = visualEffectView.bounds
        }

        window.center()
    }
}
#endif
