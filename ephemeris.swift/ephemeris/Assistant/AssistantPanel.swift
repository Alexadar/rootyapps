import SwiftUI
import EphemerisKit

/// The "Explain this screen" panel — one component, five states.
///
/// Deliberately **not a sheet**. A modal sheet buries the wheel a newcomer just asked about, and a
/// half-height sheet buries it too, because the interesting content is centred. This coexists with
/// the content: on iPhone it docks below it, on iPad and macOS it is a column the content reflows
/// beside. See `AssistantPlacement` for how each is achieved.
struct AssistantPanel: View {
    @ObservedObject var presenter: AssistantPresenter

    @StateObject private var engine = AssistantEngine()
    @State private var question = ""
    @Environment(\.locale) private var locale
    @FocusState private var focused: Bool

    private var unavailable: AssistantEngine.Unavailable? {
        AssistantEngine.unavailableReason(locale: locale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(NebulaPalette.divider)
            if let unavailable {
                unavailableBody(unavailable)
            } else {
                body(for: presenter.answer)
            }
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().overlay(NebulaPalette.cardBorder) }
        // A downward drag folds it, as the design specifies — the chevron is the discoverable path
        // and the drag is the one a thumb reaches for.
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { if $0.translation.height > 24 { withAnimation(.snappy) { presenter.collapse() } } }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("assistant.panel")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(NebulaPalette.accent)
            Text("Explain this screen").font(.subheadline).bold()
            Spacer()
            Button { withAnimation(.snappy) { presenter.collapse() } } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .help("Hide")
            .accessibilityIdentifier("assistant.collapse")

            Button { withAnimation(.snappy) { presenter.close() } } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Close")
            .accessibilityIdentifier("assistant.close")
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - States

    @ViewBuilder
    private func body(for answer: AssistantPresenter.Answer?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if engine.isAnswering {
                    working
                } else if let answer {
                    answered(answer)
                } else if let failure = engine.failure {
                    Text(verbatim: failure)
                        .font(.callout).foregroundStyle(NebulaPalette.textSecondary)
                        .accessibilityIdentifier("assistant.failure")
                } else {
                    empty
                }
                controls
                footer
            }
            .padding(14)
        }
    }

    private var empty: some View {
        Text("Ask about anything on this screen, or tap the button below.")
            .font(.callout).foregroundStyle(NebulaPalette.textSecondary)
            .accessibilityIdentifier("assistant.empty")
    }

    private var working: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Reading this screen…").font(.callout)
                .foregroundStyle(NebulaPalette.textSecondary)
        }
        .accessibilityIdentifier("assistant.working")
    }

    @ViewBuilder
    private func answered(_ answer: AssistantPresenter.Answer) -> some View {
        // ⚠️ An answer carried from another screen is dimmed and labelled rather than shown as if it
        // described what is now in front of the user.
        if presenter.heldAnswerIsFromAnotherScreen {
            Label {
                Text("Asked on: \(answer.originTitle)")
            } icon: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .font(.caption2)
            .foregroundStyle(NebulaPalette.textFaint)
            .accessibilityIdentifier("assistant.origin")
        }

        Text(verbatim: answer.text)
            .font(.callout)
            .textSelection(.enabled)
            .opacity(presenter.heldAnswerIsFromAnotherScreen ? 0.55 : 1)
            .accessibilityIdentifier("assistant.answer")

        truncationNotice(answer.truncation)
    }

    /// ⚠️ A cyan tick, **not** an amber warning, and not dismissable.
    ///
    /// Bound between the answer and the footer so it scrolls with the answer it qualifies. An amber
    /// badge would read as "something went wrong" when the correct reading is "this is partial and
    /// deliberately so" — and a dismissable one would let the very reader who needs it remove it.
    @ViewBuilder
    private func truncationNotice(_ omitted: ScreenContext.Omission?) -> some View {
        if let omitted, omitted.hidden > 0 {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(NebulaPalette.accentCyan)
                Text("Answered from \(omitted.shown) of \(omitted.total) items on this screen, chosen by \(omitted.ranking).")
            }
            .font(.caption2)
            .foregroundStyle(NebulaPalette.textFaint)
            .accessibilityIdentifier("assistant.truncation")
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Ask a question", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(askTyped)
                    .accessibilityIdentifier("assistant.question")
                Button("Ask", action: askTyped)
                    .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || engine.isAnswering)
                    .accessibilityIdentifier("assistant.ask")
            }
            Button { ask(String(localized: "What's on this screen?")) } label: {
                Label("What's on this screen?", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(engine.isAnswering)
            .accessibilityIdentifier("assistant.whatsHere")
        }
    }

    private var footer: some View {
        Text("Explanations are generated on your device from what this screen shows. They describe and define — they never calculate. Nothing is sent anywhere.")
            .font(.caption2)
            .foregroundStyle(NebulaPalette.textFaint)
            .accessibilityIdentifier("assistant.footer")
    }

    private func askTyped() {
        let q = question.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        focused = false
        ask(q)
    }

    private func ask(_ q: String) {
        guard let context = presenter.context?() else { return }
        question = ""
        Task {
            await engine.ask(q, context: context, locale: locale)
            if let text = engine.answer { presenter.store(text, from: context) }
        }
    }

    // MARK: - Unavailable

    private func unavailableBody(_ reason: AssistantEngine.Unavailable) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: reason.message)
                .font(.callout).foregroundStyle(NebulaPalette.textSecondary)
                .accessibilityIdentifier("assistant.unavailable")
            Text("Everything else in the app works as usual.")
                .font(.caption2).foregroundStyle(NebulaPalette.textFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }
}

// MARK: - The peek pill

/// What "hide" leaves behind.
///
/// The cyan dot is load-bearing: it is how the user knows an answer is still held rather than the
/// pill being a fresh, empty entry point. Tapping restores the identical answer — re-opening to a
/// blank window would defeat the reason they hid it.
struct AssistantPill: View {
    @ObservedObject var presenter: AssistantPresenter

    var body: some View {
        Button { withAnimation(.snappy) { presenter.open() } } label: {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                Text("Explain")
                if presenter.answer != nil {
                    Circle()
                        .fill(NebulaPalette.accentCyan)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
            }
            .font(.caption).bold()
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(.ultraThinMaterial, in: .capsule)
            .overlay(Capsule().strokeBorder(NebulaPalette.cardBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(presenter.answer != nil
                            ? Text("Explain this screen, answer held")
                            : Text("Explain this screen"))
        .accessibilityIdentifier("assistant.pill")
    }
}

// MARK: - Entry point

/// The ✨ toolbar item.
///
/// A toolbar item rather than a floating bubble: the app already has a toolbar idiom (the gear, the
/// export ⤴), and on iPhone a floating control would sit on top of the Liquid Glass tab bar. Present
/// only when the feature is switched on, so the chrome does not grow for people who do not want it.
/// ⚠️ Must be applied to **every screen that supplies its own navigation bar**, not once at the
/// root. A pushed destination replaces the shell's toolbar with its own, so a single item attached
/// to the root vanishes the moment the user opens the moon calendar — which is exactly the screen
/// most likely to prompt "what is this?". Caught by a UI test on that destination.
struct AssistantToolbar: ViewModifier {
    /// Read from the environment so a screen deep in a stack can add the item without the presenter
    /// being threaded through every intermediate view.
    @Environment(\.assistantPresenter) private var presenter
    @AppStorage("assistant.enabled") private var enabled = false

    func body(content: Content) -> some View {
        content.toolbar {
            if enabled {
                ToolbarItem(placement: .primaryAction) {
                    Button { withAnimation(.snappy) { presenter.toggle() } } label: {
                        Image(systemName: "sparkles")
                    }
                    .help("Explain this screen")
                    .accessibilityIdentifier("toolbar.assistant")
                }
            }
        }
    }
}

extension View {
    func assistantToolbar() -> some View { modifier(AssistantToolbar()) }
}
