import SwiftUI
import EphemerisKit

/// Whether the assistant is open, folded to its pill, or absent — and what answer it is holding.
///
/// ## Why this is app-level and not a `@State` in a view
///
/// The panel has to outlive the screen that opened it. A held answer must survive a tab change, a
/// push, and a collapse; a `@State` inside a screen dies with the screen, which is exactly what the
/// modal sheet this replaces did.
///
/// ## Hiding and navigating are different, and conflating them is the bug
///
/// - **Hiding** folds the panel to a pill and keeps the answer *exactly*. Re-opening to a blank
///   window would be the worst outcome: the user hid it precisely so they could look at the thing it
///   described, and they expect to come back to the same words.
/// - **Navigating** is not hiding. The answer is *about the screen it was asked on*, so carrying it
///   silently onto another screen is actively wrong — it would read as a description of whatever is
///   now in front of the user. So navigation collapses the panel and **stamps the answer with its
///   origin**; re-opening elsewhere shows it dimmed and labelled "Asked on: …".
@MainActor
final class AssistantPresenter: ObservableObject {

    enum Mode: Equatable {
        /// No panel at all. The ✨ toolbar item is the only way in, and only when the feature is on.
        case closed
        /// The panel is showing.
        case open
        /// Folded to the peek pill. An answer may still be held — the cyan dot says so.
        case collapsed
    }

    /// An answer and the screen it belongs to.
    struct Answer: Equatable {
        let text: String
        /// The screen this was asked on. Kept so the answer can be labelled once the user moves.
        let originID: String
        let originTitle: String
        /// Carried from the context so the disclosure travels with the answer rather than being
        /// recomputed against a screen that has since changed.
        let truncation: ScreenContext.Omission?

        /// True once the user has navigated away from where it was asked.
        var isStale = false
    }

    /// Settable rather than `private(set)`: `.inspector` needs a two-way `Bool` binding, and
    /// `AssistantPlacement` bridges it through `mode(open:)` so dismissing the column collapses to
    /// the pill instead of discarding a held answer.
    @Published var mode: Mode = .closed
    @Published private(set) var answer: Answer?

    /// The context for whatever screen is currently showing.
    ///
    /// A closure, not a stored value: the screen's data moves as the user scrubs the date, and a
    /// context captured when the screen appeared would explain a moment that has passed.
    var context: (() -> ScreenContext)?

    /// The screen currently on top, so a change can be detected.
    private(set) var currentScreenID: String?

    // MARK: - Opening and hiding

    func open() { mode = .open }

    /// The collapse chevron and the downward drag both land here. The answer is untouched.
    func collapse() { mode = .collapsed }

    /// Closes and forgets. Only the explicit ⤬ does this — hiding must never discard.
    func close() {
        mode = .closed
        answer = nil
    }

    func toggle() {
        switch mode {
        case .closed, .collapsed: mode = .open
        case .open:               mode = .collapsed
        }
    }

    func store(_ text: String, from context: ScreenContext) {
        answer = Answer(text: text,
                        originID: context.screen.id,
                        originTitle: context.screen.title,
                        truncation: context.omitted)
    }

    // MARK: - Navigation

    /// Called by whichever surface is showing, with its own context.
    ///
    /// Registering the context and noticing a screen change are one call on purpose: they are the
    /// same event, and splitting them is how the two drift apart — a panel that explains screen A
    /// while labelled screen B.
    func present(_ screen: ScreenContext.ScreenID, context: @escaping () -> ScreenContext) {
        self.context = context
        guard currentScreenID != screen.id else { return }
        currentScreenID = screen.id

        // Moving marks the held answer as belonging elsewhere, and folds the panel away so the new
        // screen is not covered by an explanation of the old one.
        if answer != nil {
            answer?.isStale = true
            if mode == .open { mode = .collapsed }
        } else if mode == .open {
            // Nothing held, so there is nothing to preserve — but an empty panel following the user
            // from screen to screen is clutter rather than help.
            mode = .collapsed
        }
    }

    /// Whether the held answer was asked somewhere else.
    var heldAnswerIsFromAnotherScreen: Bool {
        guard let answer else { return false }
        return answer.isStale || answer.originID != currentScreenID
    }
}


// MARK: - Environment

/// The presenter reaches descendants through the environment rather than a parameter on every view.
///
/// A screen deep in a navigation stack — the chart detail, the astrocartography map — has to
/// register its context, and threading the presenter through each intermediate view would add a
/// parameter to files that otherwise have nothing to do with the assistant.
///
/// The default is a fresh presenter rather than an optional: a view used in a preview or a test
/// without a shell still renders, and registering a context on a presenter nobody displays is
/// harmless.
private struct AssistantPresenterKey: EnvironmentKey {
    @MainActor static let defaultValue = AssistantPresenter()
}

extension EnvironmentValues {
    var assistantPresenter: AssistantPresenter {
        get { self[AssistantPresenterKey.self] }
        set { self[AssistantPresenterKey.self] = newValue }
    }
}
