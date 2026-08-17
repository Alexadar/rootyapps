#if !os(macOS)
import SwiftUI
import GenerationKit

/// iPad — where the two screens merge (bundle `1d`).
///
/// With room to spare, Create stops being a screen and becomes a toolbar over the gallery: type, tap
/// Create, and the new wallpaper forms in place. The aspect override appears here and not on the
/// phone because an iPad genuinely rotates, so "which shape is this wallpaper" is a real question
/// rather than a setting nobody needs.
struct PadRoot: View {
    @Environment(\.colorScheme) private var scheme
    @FocusState private var promptFocused: Bool

    var create: CreateModel
    var library: LibraryModel
    var resume: ResumeModel
    /// **Concrete, not `any WallpaperActions`.** `@Observable` tracking does not see through an
    /// existential, so mutations to `handoff` never invalidated this view and the handoff sheet
    /// simply never appeared — the save had happened, with nothing on screen to say so.
    var actions: IOSWallpaperActions
    var onUsePrompt: (String) -> Void

    var body: some View {
        ZStack {
            AmbientBackground(recent: library.mostRecentImage)

            VStack(spacing: 0) {
                createToolbar
                    .padding(.horizontal, WP.Space.margin)
                    .padding(.top, WP.Space.grid)

                GalleryView(library: library, create: create, actions: actions,
                            onUsePrompt: onUsePrompt,
                            onSurpriseMe: create.surpriseMe,
                            columns: 4,
                            tileAspect: 3.0 / 4.0,
                            bottomInset: WP.Space.section,
                            // iPad only. The phone's two columns leave no room beside a 2×2 hero,
                            // and `GalleryLayout.split` refuses it below four regardless.
                            featured: true)
            }

            if create.isRunning || create.morphStage == .result || create.morphStage == .failure {
                // The job forms over the grid rather than on a screen of its own — same glass
                // object, same morph, different surroundings.
                JobMorph(model: create,
                         onStart: { create.createTapped(saveTo: library) },
                         onCancel: create.cancel,
                         onPrimaryAction: primaryAction,
                         onShare: share,
                         onRegenerate: { create.regenerate(saveTo: library) },
                         onRetry: { create.start(saveTo: library) },
                         onEditPrompt: create.dismissResult,
                         primaryActionTitle: actions.primaryActionTitle,
                         enhance: EnhanceAffordance.make(for: create.finishedRecord,
                                                         model: create, library: library))
            }

            VStack(spacing: WP.Space.gap) {
                Spacer()
                BottomShelf(create: create, resume: resume, library: library)
                HStack {
                    Spacer()
                    aspectChip
                }
            }
            .padding(WP.Space.margin)
        }
        .sheet(item: handoffBinding) { HandoffSheet(handoff: $0) }
    }

    private var createToolbar: some View {
        HStack(spacing: WP.Space.gap) {
            PromptField(text: Bindable(create).prompt, focused: $promptFocused)
                .frame(width: 420, height: 56)

            Button(action: create.surpriseMe) {
                Label("Surprise me", systemImage: "sparkles")
                    .wpFont(.control)
                    .foregroundStyle(WP.ink(scheme))
                    .padding(.horizontal, WP.Space.grid)
                    .frame(height: WP.pillHeight)
            }
            .buttonStyle(.plain)
            .wpGlassCapsule(.interactive)

            Button { create.createTapped(saveTo: library) } label: {
                Text("Create")
                    .wpFont(.button)
                    .foregroundStyle(GlassLabel.color(on: create.canStart ? .tinted : .regular,
                                                      scheme: scheme, enabled: create.canStart))
                    .padding(.horizontal, 30)
                    .frame(height: WP.pillHeight)
            }
            .buttonStyle(.plain)
            .wpGlassCapsule(create.canStart ? .tinted : .regular)
            // NOT `.disabled(!create.canStart)`. A disabled button cannot be tapped, so it cannot
            // explain why it refused — and "one thing at a time" is exactly what the user needs to
            // hear when Create greys out mid-Enhance. The label already carries the disabled ink.
            .accessibilityHint(create.canStart ? "" : EnhanceCopy.oneThingAtATime)

            Spacer()
        }
    }

    /// Quiet, and out of the way. The default follows the device; the other two are there for the
    /// person who wants a phone wallpaper made on the bigger screen.
    private var aspectChip: some View {
        Menu {
            ForEach(AspectRatio.offered, id: \.self) { option in
                Button {
                    create.aspect = option
                } label: {
                    Label(option.displayName,
                          systemImage: create.aspect == option ? "checkmark" : "")
                }
            }
        } label: {
            Text(create.aspect.displayName)
                .wpFont(.caption)
                .foregroundStyle(WP.ink2(scheme))
                .padding(.horizontal, WP.Space.gap)
                .frame(height: 34)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .wpGlassCapsule(.regular, shadow: false)
        .accessibilityLabel("Wallpaper shape")
        .accessibilityValue(create.aspect.displayName)
    }

    private var handoffBinding: Binding<WallpaperHandoff?> {
        Binding(get: { actions.handoff }, set: { if $0 == nil { actions.dismissHandoff() } })
    }

    private func primaryAction() {
        guard let record = create.finishedRecord else { return }
        Task { await actions.performPrimary(on: record) }
    }

    private func share() {
        guard let record = create.finishedRecord else { return }
        actions.share(record)
    }
}
#endif
