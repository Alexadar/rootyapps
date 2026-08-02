import SwiftUI

/// Marine Nav — offline tide and current prediction, with the navigation tools
/// that go with it.
///
/// STRUCTURAL UI. This pass establishes the information architecture, the
/// navigation, and the wiring from every displayed number back to an
/// oracle-tested Kit. It is deliberately plain: no design system, no styling
/// decisions, no bespoke components. The visual design comes in a later pass.
///
/// The one rule that must survive that pass: **all math lives in the Kits.**
/// Views and view-models only format and display.
@main
struct MarineNavApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 1_100, height: 760)
        #endif
    }
}
