import SwiftUI

/// Create — two inputs and one action (bundle `2a`, states per `1a`).
///
/// The glass floats over the picture; nothing opaque ever covers it. Everything that changes state
/// during a run lives in `JobMorph`, which is the single glass object the whole screen turns around.
struct CreateView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.wpAccessibility) private var accessibility
    @FocusState private var promptFocused: Bool
    @State private var showingAdvanced = false

    var model: CreateModel
    var actions: any WallpaperActions
    var library: LibraryModel?
    /// Bottom inset so the morph clears the floating segment control.
    var bottomInset: CGFloat = 110

    var body: some View {
        ZStack {
            switch model.phase {
            case .idle, .typed:
                composing
            case .preparing, .running, .enlarging:
                generating
            case .done:
                morph(onEditPrompt: model.tweak)
            case .editing:
                editingOverImage
            case .failed:
                failed
            }
        }
        // The toast moved to `BottomShelf`, which arbitrates it against the resume offer — and
        // which every shell mounts, so iPad and Mac finally see one too.
        .animation(WPMotion.morph(reduceMotion: accessibility.reduceMotion), value: model.morphStage)
    }

    // MARK: Empty · typed

    private var composing: some View {
        // **Hard-bounded width.** `padding` alone is not enough: a child that demands more width
        // than the screen makes the whole VStack that wide, and every `maxWidth: .infinity` sibling
        // then matches it — so the field and the Create capsule overflow both edges while the
        // intrinsically-sized pills stay put. That is what shipped, and the Simulator does not
        // reproduce it because it renders `GlassEffectContainer` in a degraded form.
        //
        // Measuring the container and setting an explicit width means no child can inflate it,
        // whatever the real Liquid Glass layout does underneath.
        GeometryReader { proxy in
            composingContent
                .frame(width: max(proxy.size.width - WP.Space.margin * 2, 0))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var composingContent: some View {
        VStack(spacing: 0) {
            Text("Create")
                .wpFont(.screenTitle)
                .foregroundStyle(WP.ink(scheme))
                .padding(.top, 56)

            // Board 2a places the field at y≈230 on a 874 pt reference — a deliberate gap under the
            // title, not "whatever is left over". A Spacer here let the field claim the whole screen.
            Spacer().frame(height: 78)

            VStack(spacing: 14) {
                PromptField(text: Bindable(model).prompt, focused: $promptFocused)
                Button(action: model.surpriseMe) {
                    Label("Surprise me", systemImage: "sparkles")
                        .wpFont(.control)
                        .foregroundStyle(WP.ink(scheme))
                        .padding(.horizontal, 20)
                        .frame(height: promptFocused ? WP.compactPillHeight : WP.pillHeight)
                }
                .buttonStyle(.plain)
                .wpGlassCapsule(.interactive)
                .accessibilityHint("Writes a prompt and a negative, so you can see both and change them")
                .frame(maxWidth: .infinity, alignment: promptFocused ? .leading : .center)
                .overlay(alignment: .trailing) {
                    // One quiet disclosure; everything behind it has a working default.
                    Button { showingAdvanced = true } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(WP.ink2(scheme))
                            .frame(width: WP.minimumHitTarget, height: WP.minimumHitTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Advanced")
                }
            }

            Spacer(minLength: 0)

            // No background-loading caption here. It described `preload()`, which is deliberately
            // never called — the model loads when Create is pressed, not when Create is *looked at*.
            // `isPreloading` could therefore never be true, so this branch and the animation driving
            // it could never render, while reading like a feature the app had. The waking copy the
            // user does see belongs to the running state and lives in `stepText`.
            morph(onEditPrompt: model.dismissResult)
                .padding(.bottom, bottomInset)
        }
        .sheet(isPresented: $showingAdvanced) { AdvancedSheet(settings: model.settings) }
    }

    // MARK: Generating

    private var generating: some View {
        VStack(spacing: 0) {
            // The prompt stays on screen. A twenty-second wait during which the user cannot see
            // what they asked for is a twenty-second wait they cannot evaluate.
            Text(model.prompt)
                .wpFont(.caption)
                .foregroundStyle(WP.ink2(scheme))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 44)
                .padding(.top, WP.Space.section * 2)

            Spacer()

            morph(onEditPrompt: model.dismissResult)

            Spacer()
            Spacer(minLength: bottomInset)
        }
    }

    // MARK: Failed

    private var failed: some View {
        VStack {
            Spacer()
            morph(onEditPrompt: model.dismissResult)
            Spacer()
            Spacer(minLength: bottomInset)
        }
    }

    // MARK: Edit over the image (board 5b)

    /// The finished picture stays, behind a light scrim, while the prompt field returns over it.
    ///
    /// This is the app's real loop: change one word, re-roll. Keeping the picture visible is what
    /// makes it a loop rather than a restart — the user can see what they are adjusting away from.
    /// iPhone only; on iPad and Mac the field never left, so *Tweak* just refocuses the toolbar.
    private var editingOverImage: some View {
        ZStack {
            if let finished = model.finished {
                // Measured against the screen, not the picture. An unclipped `scaledToFill` sizes
                // to the image — 2048 × 2048 — and the ZStack takes that size, so returning here
                // from a finished wallpaper blew the layout up again. Same failure as the ambient
                // background; this was the last one left.
                GeometryReader { proxy in
                    Image(platformImage: finished)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
                .accessibilityHidden(true)
            }
            Rectangle()
                .fill(.white.opacity(0.28))
                .background(.clear)
                .blur(radius: 8)
                .allowsHitTesting(false)

            VStack(spacing: 14) {
                PromptField(text: Bindable(model).prompt, focused: $promptFocused)
                HStack {
                    Button(action: model.surpriseMe) {
                        Label("Surprise me", systemImage: "sparkles")
                            .wpFont(.caption)
                            .foregroundStyle(WP.ink(scheme))
                            .padding(.horizontal, 16)
                            .frame(height: WP.compactPillHeight)
                    }
                    .buttonStyle(.plain)
                    .wpGlassCapsule(.interactive)

                    Spacer()

                    Button { model.regenerate(saveTo: library) } label: {
                        // "Regenerate", not "Create" — the user is iterating on the picture behind
                        // this field, not starting from nothing.
                        Text(model.primaryVerb)
                            .wpFont(.button)
                            .foregroundStyle(GlassLabel.color(on: model.canStart ? .tinted : .regular,
                                                              scheme: scheme, enabled: model.canStart))
                            .padding(.horizontal, 26)
                            .frame(height: WP.pillHeight)
                    }
                    .buttonStyle(.plain)
                    .wpGlassCapsule(model.canStart ? .tinted : .regular)
                    // NOT `.disabled(!model.canStart)`. A disabled button cannot be tapped, so it
                    // cannot explain why it refused — and "one thing at a time" is exactly what the
                    // user needs to hear when Create greys out mid-Enhance. The label already
                    // carries the disabled ink. The Mac and iPad shells were fixed for this; the
                    // phone was missed, which left `explainBusy()` unreachable from the primary
                    // shell — the one where the toast matters most.
                    .accessibilityHint(model.canStart ? "" : EnhanceCopy.oneThingAtATime)
                }
            }
            .padding(.horizontal, WP.Space.margin)
            .padding(.top, 150)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            Button(action: model.cancelEditing) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WP.ink(scheme).opacity(0.7))
                    .frame(width: WP.minimumHitTarget, height: WP.minimumHitTarget)
            }
            .buttonStyle(.plain)
            .wpGlass(.regular, in: Circle())
            .padding(.leading, 16)
            .padding(.top, 70)
            .accessibilityLabel("Keep this wallpaper")
        }
        .onAppear { promptFocused = true }
    }

    private func morph(onEditPrompt: @escaping () -> Void) -> some View {
        JobMorph(model: model, onStart: start, onCancel: model.cancel,
                 onPrimaryAction: primaryAction, onShare: share,
                 onRegenerate: { model.regenerate(saveTo: library) },
                 onRetry: start, onEditPrompt: onEditPrompt,
                 primaryActionTitle: actions.primaryActionTitle,
                 enhance: EnhanceAffordance.make(for: model.finishedRecord,
                                                 model: model, library: library))
    }

    private func start() {
        promptFocused = false
        model.createTapped(saveTo: library)
    }

    private func primaryAction() {
        guard let record = model.finishedRecord else { return }
        Task { await actions.performPrimary(on: record) }
    }

    private func share() {
        guard let record = model.finishedRecord else { return }
        actions.share(record)
    }

    /// `nil` unless there is a saved wallpaper and the tile models are installed.
}

/// The prompt field — the primary object on the screen, and the reason the type ramp has a
/// deliberately oversized 19 pt style.
struct PromptField: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    /// The field's own height, because it cannot be imposed from outside.
    ///
    /// A fixed `.frame(height:)` inside a view ignores whatever the parent proposes, so the Mac
    /// toolbar's `.frame(height: 52)` was silently losing to the 148 below and taking the whole
    /// toolbar row to 148 with it. The height has to be a parameter or the two disagree forever.
    var height: CGFloat = 148

    /// Vertical inset, compressed only when the field is too short to seat one line at the design
    /// value. At the default 148 this is exactly the 14 it has always been, so the phone and iPad
    /// render identically; it only gives ground in a short field, where 14 would clip.
    private var inset: CGFloat {
        let line: CGFloat = 23              // one line of the 19 pt prompt style
        return min(14, max(4, (height - line) / 2))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Describe a wallpaper…")
                    .wpFont(.prompt)
                    .foregroundStyle(WP.ink3(scheme))
                    .padding(.horizontal, 22)
                    // **Top only.** The ZStack is `.topLeading`, so a symmetric inset here changes
                    // nothing about where the placeholder sits and only inflates its intrinsic
                    // height — 20 + 23 + 20 = 63, which overflows a 52 pt toolbar field while
                    // looking correct at 148. The +6 matches `TextEditor`'s own internal text
                    // origin, which is also why the horizontal insets differ by 4.
                    .padding(.top, inset + 6)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .wpFont(.prompt)
                .foregroundStyle(WP.ink(scheme))
                .scrollContentBackground(.hidden)
                .background(.clear)
                .padding(.horizontal, 18)
                .padding(.vertical, inset)
                .focused(focused)
                .tint(WP.accent)
        }
        // **Fixed, not greedy.** `TextEditor` has no intrinsic height and expands to fill whatever
        // it is given, so inside a VStack with a Spacer it swallows the screen — which is exactly
        // what it did. 148 pt is the board's min-height; growth with long prompts is a separate
        // change and needs a max, or the bug comes straight back.
        .frame(height: height, alignment: .topLeading)
        .wpGlassCard()
        .accessibilityLabel("Prompt")
        .accessibilityHint("Describe the wallpaper you want")
    }
}
