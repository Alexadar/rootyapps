import Testing
import Foundation
import EphemerisKit
@testable import Ephemeris

/// The panel's state machine.
///
/// Tested here rather than through the UI because the interesting properties involve a **held
/// answer**, and generating one needs eligible hardware and several seconds. A UI test that folds an
/// empty panel and finds it still empty proves nothing — it passed with `collapse()` deliberately
/// discarding the answer, which is why these exist.
@Suite("Assistant presenter")
@MainActor
struct AssistantPresenterTests {

    private func screen(_ id: String, _ title: String) -> ScreenContext.ScreenID {
        .init(id: id, title: title)
    }

    private func context(_ id: String, _ title: String,
                         omitted: ScreenContext.Omission? = nil) -> ScreenContext {
        ScreenContext(screen: screen(id, title), gate: .place, situation: "test",
                      schema: [], rows: [.init(title: "row", fields: [])], omitted: omitted)
    }

    // MARK: - Hiding keeps the answer

    /// ⚠️ The whole point of the pill. Re-opening to a blank window would defeat the reason the user
    /// hid it: they folded it away *to look at the thing it described*.
    @Test func collapsingKeepsTheAnswerAndClosingDiscardsIt() {
        let p = AssistantPresenter()
        let ctx = context("sky.wheel", "Sky · chart wheel")
        p.present(ctx.screen) { ctx }
        p.open()
        p.store("The wheel shows ten bodies.", from: ctx)
        #expect(p.answer?.text == "The wheel shows ten bodies.")

        p.collapse()
        #expect(p.mode == .collapsed)
        #expect(p.answer?.text == "The wheel shows ten bodies.", "hiding must never discard the answer")

        p.open()
        #expect(p.answer?.text == "The wheel shows ten bodies.", "re-opening must restore it exactly")

        // Only the explicit close forgets.
        p.close()
        #expect(p.mode == .closed)
        #expect(p.answer == nil, "closing is the one action that discards")
    }

    // MARK: - Navigating is not hiding

    /// The answer is about the screen it was asked on, so carrying it silently onto another screen
    /// would read as a description of whatever is now in front of the user.
    @Test func navigatingStampsTheAnswerWithItsOriginAndFoldsThePanel() {
        let p = AssistantPresenter()
        let sky = context("sky.wheel", "Sky · chart wheel")
        p.present(sky.screen) { sky }
        p.open()
        p.store("The wheel shows ten bodies.", from: sky)
        #expect(!p.heldAnswerIsFromAnotherScreen)

        let moon = context("sky.moon", "Moon calendar")
        p.present(moon.screen) { moon }

        #expect(p.mode == .collapsed, "moving must fold the panel away from the new screen")
        #expect(p.answer?.text == "The wheel shows ten bodies.", "the answer is kept, not dropped")
        #expect(p.heldAnswerIsFromAnotherScreen, "it must be marked as belonging elsewhere")
        #expect(p.answer?.originTitle == "Sky · chart wheel",
                "the label must name where it was asked, so the user is not misled")
    }

    /// Re-presenting the same screen is not navigation and must not mark anything stale.
    @Test func stayingOnAScreenDoesNotStaleTheAnswer() {
        let p = AssistantPresenter()
        let sky = context("sky.wheel", "Sky · chart wheel")
        p.present(sky.screen) { sky }
        p.open()
        p.store("An answer.", from: sky)

        p.present(sky.screen) { sky }   // e.g. a date scrub re-registering the same screen
        #expect(p.mode == .open, "the panel must not fold when nothing moved")
        #expect(!p.heldAnswerIsFromAnotherScreen)
    }

    /// With nothing held, moving still folds an open panel — an empty panel trailing the user from
    /// screen to screen is clutter, not help.
    @Test func anEmptyPanelFoldsOnNavigationToo() {
        let p = AssistantPresenter()
        let sky = context("sky.wheel", "Sky")
        p.present(sky.screen) { sky }
        p.open()
        p.present(screen("sky.moon", "Moon")) { self.context("sky.moon", "Moon") }
        #expect(p.mode == .collapsed)
        #expect(p.answer == nil)
    }

    // MARK: - The truncation travels with the answer

    /// Carried on the answer rather than recomputed, so the disclosure cannot drift away from the
    /// text it qualifies once the underlying screen changes.
    @Test func theOmissionIsStoredWithTheAnswer() {
        let p = AssistantPresenter()
        let ctx = context("cycles.timeline", "Timeline",
                          omitted: .init(shown: 4, total: 104, ranking: "nearest to now"))
        p.present(ctx.screen) { ctx }
        p.store("Four of them.", from: ctx)

        #expect(p.answer?.truncation?.total == 104)
        #expect(p.answer?.truncation?.shown == 4)
        #expect(p.answer?.truncation?.hidden == 100)
    }

    // MARK: - Toggling

    @Test func togglingAlternatesOpenAndCollapsed() {
        let p = AssistantPresenter()
        #expect(p.mode == .closed)
        p.toggle(); #expect(p.mode == .open)
        p.toggle(); #expect(p.mode == .collapsed)
        p.toggle(); #expect(p.mode == .open)
    }
}
