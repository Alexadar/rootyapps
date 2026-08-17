import SwiftUI
import EphemerisKit

/// How the panel sits on screen without covering what it describes.
///
/// One component, two presentations — chosen by width, not by platform, so an iPad in Slide Over
/// gets the phone treatment rather than a column squeezed into 320 points.
///
/// ## Compact: a safe-area inset, not an overlay
///
/// `.safeAreaInset(edge: .bottom)` is the whole trick, and the choice is not cosmetic. An overlay
/// (`.overlay(alignment: .bottom)`) draws the panel *on top* — the content is still there, still
/// laid out at full height, and the bottom third of it is simply hidden behind glass. That is a
/// modal sheet with extra steps, and it fails the one requirement this design exists to meet.
///
/// A safe-area inset instead **shrinks the content's usable area**. The enclosing `ScrollView`
/// reflows above it and its scroll range grows, so every row remains reachable and the focal content
/// rises into the clear band. That is what the design means by "nudges the focal content up".
///
/// ## Regular: a real column
///
/// `.inspector()` is a genuine split, not a floating layer: the content lays out in the width that
/// remains. Closing it returns that width. Nothing is ever occluded.
struct AssistantPlacement: ViewModifier {
    @ObservedObject var presenter: AssistantPresenter
    @AppStorage("assistant.enabled") private var enabled = false

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSize
    private var isCompact: Bool { hSize == .compact }
    #else
    private var isCompact: Bool { false }
    #endif

    func body(content: Content) -> some View {
        // Switched off means genuinely absent — no inset, no column, no reserved space.
        if !enabled {
            content
        } else if isCompact {
            content
                .safeAreaInset(edge: .bottom, spacing: 0) { compactDock }
        } else {
            content
                .inspector(isPresented: Binding(
                    get: { presenter.mode == .open },
                    set: { presenter.mode(open: $0) })) {
                        AssistantPanel(presenter: presenter)
                            .inspectorColumnWidth(min: 280, ideal: 340, max: 460)
                    }
                // The pill is the way back once the column is closed. On regular width it sits with
                // the content rather than over it, so it costs a line and hides nothing.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if presenter.mode != .open { pillBar }
                }
        }
    }

    /// The docked panel, or the pill it folds to.
    @ViewBuilder private var compactDock: some View {
        switch presenter.mode {
        case .open:
            AssistantPanel(presenter: presenter)
                // A FIXED height, not `maxHeight`. The panel contains a ScrollView, which happily
                // takes every point offered — measured at 403pt of an 874pt screen under a
                // `maxHeight` cap, i.e. nearly half the display for a two-paragraph answer. A hard
                // height keeps the content it explains the larger half; the answer scrolls inside.
                .frame(height: 300)
                .transition(.move(edge: .bottom))
        case .collapsed:
            pillBar
        case .closed:
            // Genuinely nothing: no inset, so the content has its full height back.
            EmptyView()
        }
    }

    private var pillBar: some View {
        HStack {
            Spacer()
            AssistantPill(presenter: presenter)
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

extension AssistantPresenter {
    /// Bridges `.inspector`'s `Bool` binding to the three-state mode without discarding a held
    /// answer: dismissing the column collapses to the pill rather than closing.
    func mode(open: Bool) {
        if open { self.open() } else if answer != nil { collapse() } else { close() }
    }
}

extension View {
    func assistantPlacement(_ presenter: AssistantPresenter) -> some View {
        modifier(AssistantPlacement(presenter: presenter))
    }

    /// Registers this screen's context with the presenter, and reports the change.
    ///
    /// Both in one call: they are the same event, and separating them is how a panel ends up
    /// explaining one screen while labelled another.
    func assistantContext(_ presenter: AssistantPresenter,
                          screen: ScreenContext.ScreenID,
                          context: @escaping () -> ScreenContext) -> some View {
        onAppear { presenter.present(screen, context: context) }
    }
}
