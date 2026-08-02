import Testing
import Foundation
@testable import KerfCalc

/// `Router.open(_:)` — the one function that has to satisfy BOTH layouts at once.
///
/// ## Why this is worth its own suite
///
/// Compact and regular are different navigation models: compact has a `TabView` driven by
/// `selectedTab` and a `NavigationStack` path; regular has a rail driven by `surface`, a trade sidebar
/// driven by `category`, and a `sidebar` selection. `open(_:)` must set all five consistently, and
/// setting only the ones the *current* layout reads is a bug that appears when the window is resized or
/// when the same build runs on the other device.
///
/// kerfcalc has already shipped a version of this: a deep link seeded the stack path without selecting
/// its tab, so the tool was pushed onto a stack nobody could see — and an iPad App Store screenshot of
/// the Spec keypad went out captioned as a formula screen. `Router` had no test until now.
@MainActor
@Suite struct RouterTests {

    @Test func openSetsEveryLayoutsStateAtOnce() {
        let r = Router()
        r.open(.miter)

        #expect(r.selectedTab == 1, "compact: the Formulas tab must be selected")
        #expect(r.surface == .formulas, "regular: the rail must show the Formulas surface")
        #expect(r.category == Tool.miter.section, "regular: the sidebar must follow the tool's trade")
        #expect(r.formulasPath == [.miter], "compact: the tool must be pushed onto the stack")
        #expect(r.sidebar == .tool(.miter), "regular: the sidebar selection must be the tool")
    }

    /// Every tool, not just one — a section mapping that is wrong for a single trade would otherwise
    /// only surface for that one screen.
    @Test func openWorksForEveryToolInTheCatalog() {
        for t in Tool.allCases {
            let r = Router()
            r.open(t)
            #expect(r.selectedTab == 1, "\(t.rawValue) did not select the Formulas tab")
            #expect(r.surface == .formulas, "\(t.rawValue) did not select the Formulas surface")
            #expect(r.category == t.section, "\(t.rawValue) put the sidebar on the wrong trade")
            #expect(r.sidebar == .tool(t))
            #expect(r.formulasPath.last == t)
        }
    }

    /// Opening the same tool twice must not stack two copies — otherwise Back appears to do nothing.
    @Test func openingTheSameToolTwiceDoesNotStackIt() {
        let r = Router()
        r.open(.rafter)
        r.open(.rafter)
        #expect(r.formulasPath == [.rafter], "the same tool was pushed twice: \(r.formulasPath)")
    }

    /// Opening a different tool pushes it, so Back returns to the previous one.
    @Test func openingADifferentToolPushesIt() {
        let r = Router()
        r.open(.rafter)
        r.open(.stairs)
        #expect(r.formulasPath == [.rafter, .stairs])
        #expect(r.sidebar == .tool(.stairs))
        #expect(r.category == Tool.stairs.section)
    }

    /// A fresh Router with no launch override starts on Spec in both layouts. This is the default the
    /// screenshot pipeline relies on, and `Surface(rawValue:)` must agree with `selectedTab`.
    @Test func defaultLaunchIsSpecInBothLayouts() {
        let r = Router()
        #expect(r.selectedTab == 0)
        #expect(r.surface == .spec)
        #expect(r.formulasPath.isEmpty)
        #expect(r.sidebar == .spec)
        #expect(r.category == nil)
    }

    /// The compact tab index and the regular surface are two encodings of one idea, so every tab index
    /// must map to a surface. A missing case would silently fall back to Spec for that tab.
    @Test func everyTabIndexHasASurface() {
        for s in Router.Surface.allCases {
            #expect(Router.Surface(rawValue: s.rawValue) == s)
        }
        #expect(Router.Surface(rawValue: 0) == .spec)
        #expect(Router.Surface(rawValue: 1) == .formulas)
        #expect(Router.Surface(rawValue: 2) == .reference)
    }
}
