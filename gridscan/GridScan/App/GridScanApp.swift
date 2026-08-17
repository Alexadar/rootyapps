import SwiftUI

// First run asks for nothing: no account, no org, no email. The Library teaches the
// ways in; nothing auto-presents at launch.
@main
struct GridScanApp: App {
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
#if os(macOS)
        WindowGroup {
            RootView()
                .environmentObject(environment)
        }
        .defaultSize(width: 1200, height: 820)
#else
        WindowGroup {
            RootView()
                .environmentObject(environment)
        }
#endif
    }
}
