import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

@main
struct AirCoreApp: App {

    @State private var settings: AppSettings
    @State private var models: AppModels
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Persistence.resetIfRequested()
        _settings = State(initialValue: .loaded())
        _models = State(initialValue: .loaded())
    }

    /// `light` / `dark` from `AIRCORE_APPEARANCE`, or `nil` — follow the system — everywhere else.
    static let captureColorScheme: ColorScheme? = {
        switch LaunchOverride.value("AIRCORE_APPEARANCE")?.lowercased() {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }()

    #if os(macOS)
    /// The opening window size — 1180×820 for a person, overridable for capture.
    ///
    /// A Mac app preview must be delivered at 1920×1080, and this window is 1.44:1, so fitting it
    /// to 16:9 meant scaling to width and cropping 19 % off the bottom — which on the pipe screen
    /// took the Darcy-vs-Hazen–Williams comparison with it, the exact thing that scene's caption
    /// points at. Recording a 16:9 window instead makes the fit a pure downscale with no crop at
    /// all, so nothing is lost and nothing is upscaled.
    ///
    /// `AIRCORE_WINDOW` goes through `LaunchOverride`, so like every other capture hook it reads as
    /// `nil` in Release and the shipping app has one window size.
    static let defaultWindow: CGSize = {
        let fallback = CGSize(width: 1180, height: 820)
        guard let raw = LaunchOverride.value("AIRCORE_WINDOW") else { return fallback }
        let parts = raw.lowercased().split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2, parts[0] >= 900, parts[1] >= 560 else { return fallback }
        return CGSize(width: parts[0], height: parts[1])
    }()
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(models)
                .tint(DS.water)
                // Capture must not depend on what time of day it runs at.
                //
                // Two Mac recordings seven minutes apart came out light and then dark: this machine
                // is on Auto appearance and the sun set between them. The Mac screenshots were
                // taken in daylight, so an evening recording would have shipped a dark preview onto
                // a product page of light screenshots. `nil` — every ordinary launch — leaves the
                // user's system appearance alone, which is the whole point of supporting both.
                .preferredColorScheme(Self.captureColorScheme)
                #if os(macOS)
                // `scenePhase` is the iOS lifecycle. A Mac app quits without necessarily passing
                // through it, so on macOS the same save is hung off AppKit's own notifications —
                // otherwise everything typed since launch is lost on ⌘Q, which the macOS UI suite
                // caught by typing a value, quitting, relaunching and finding the default back.
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.willTerminateNotification)) { _ in models.saveAll() }
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.willResignActiveNotification)) { _ in models.saveAll() }
                // The layout needs this much room: sidebar 220 + inspector 380 + a chart worth
                // looking at. Below it the split collapses and the Mac shows a worse layout than
                // the iPad — which is what a restored 900×450 frame was doing.
                .frame(minWidth: 900, minHeight: 560)
                #endif
        }
        #if os(macOS)
        // A desk tool, not a phone app in a window: open wide enough to put the chart beside its
        // inputs, or the split collapses and the Mac shows a worse layout than the iPad.
        //
        // `.defaultSize` and a minimum on the content — but **not**
        // `.windowResizability(.contentMinSize)`. Adding that stopped the window being created at
        // all: the app launched with a menu bar, no window, and `File ▸ Close` greyed out, and
        // every one of the 27 macOS UI tests failed with "never appeared". A window that cannot
        // resolve its resizability does not fall back to a default size, it does not open.
        //
        // Note `.defaultSize` applies only when macOS has no saved frame to restore. A window a
        // user (or a previous test run) left at 900×450 comes back at 900×450 regardless, which
        // is why the minimum above is the thing actually protecting the layout.
        .defaultSize(width: Self.defaultWindow.width, height: Self.defaultWindow.height)
        #endif
        .onChange(of: scenePhase) { _, phase in
            // Everything is written on the way out of the foreground, which is the moment before
            // the system is free to terminate the app. Saving on every keystroke instead would be
            // a UserDefaults write per digit for no benefit.
            if phase != .active { models.saveAll() }
        }
        #if os(macOS)
        .commands {
            CommandGroup(after: .pasteboard) {
                Button("Copy Table") {
                    NotificationCenter.default.post(name: .copyTable, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }
        #endif
    }
}

extension Notification.Name {
    /// ⌘⇧C, from the Mac menu bar to whichever tool is on screen.
    static let copyTable = Notification.Name("AirCore.copyTable")
}
