#if os(macOS)
import SwiftUI
import AppKit
import GenerationKit
import LibraryKit

/// Mac (bundle `3a`) — a single window, and the one platform where the app finishes the job.
///
/// Desktop-shaped output is the point: the size picker defaults to the frontmost display's own
/// resolution, because a wallpaper generated at phone proportions and stretched across a 5K display
/// is exactly what makes generated wallpapers look cheap. The window is a design object, not a
/// stretched phone screen.
struct MacRoot: View {
    @Environment(\.colorScheme) private var scheme
    @FocusState private var promptFocused: Bool

    var create: CreateModel
    var library: LibraryModel
    var resume: ResumeModel
    var actions: MacWallpaperActions
    var onUsePrompt: (String) -> Void

    @State private var selection: LibraryModel.Item?

    var body: some View {
        ZStack {
            MacPaperBackground()

            VStack(spacing: 0) {
                toolbar
                    .padding(.horizontal, WP.Space.margin)
                    .padding(.vertical, WP.Space.grid)
                grid
            }

            if create.isRunning || create.morphStage == .result || create.morphStage == .failure {
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
        }
        // Mac's first shelf — and its first toast. `cancel()` has been raising "Stopped — your
        // prompt is kept" since the beginning and nothing on this platform ever rendered it.
        .overlay(alignment: .bottom) {
            BottomShelf(create: create, resume: resume, library: library)
                .padding(.bottom, WP.Space.margin)
        }
        .onAppear {
            let pixels = MacWallpaperActions.frontmostDisplayPixels()
            create.aspect = AspectRatio.fittingDisplay(width: pixels.width, height: pixels.height)
        }
    }

    private var toolbar: some View {
        HStack(spacing: WP.Space.gap) {
            // The height goes *in*, not around. `PromptField` sets its own `.frame(height:)`, which
            // ignores whatever a parent proposes — so an outer `.frame(height: 52)` lost silently to
            // the field's 148 and took this whole toolbar row to 148 with it.
            PromptField(text: Bindable(create).prompt, focused: $promptFocused, height: 52)
                .frame(width: 420)

            Button(action: create.surpriseMe) {
                Label("Surprise me", systemImage: "sparkles")
                    .wpFont(.control)
                    .foregroundStyle(WP.ink(scheme))
                    .padding(.horizontal, WP.Space.grid)
                    .frame(height: WP.pillHeight)
            }
            .buttonStyle(.plain)
            .wpGlassCapsule(.interactive)

            sizePicker

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

    /// "This display · 5120 × 2880" — the honest default, with the two portable shapes below it.
    private var sizePicker: some View {
        Menu {
            Button("This display · \(displayAspect.pixelDescription)") { create.aspect = displayAspect }
            Divider()
            ForEach(AspectRatio.offered, id: \.self) { option in
                Button("\(option.displayName) · \(option.pixelDescription)") { create.aspect = option }
            }
        } label: {
            Text(create.aspect == displayAspect
                 ? "This display · \(displayAspect.pixelDescription)"
                 : "\(create.aspect.displayName) · \(create.aspect.pixelDescription)")
                .wpFont(.control, tabularNumbers: true)
                .foregroundStyle(WP.ink2(scheme))
                .padding(.horizontal, WP.Space.gap)
                .frame(height: WP.pillHeight)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .wpGlassCapsule(.regular, shadow: false)
        .accessibilityLabel("Wallpaper size")
    }

    private var displayAspect: AspectRatio {
        let pixels = MacWallpaperActions.frontmostDisplayPixels()
        return AspectRatio.fittingDisplay(width: pixels.width, height: pixels.height)
    }

    private var grid: some View {
        ScrollView {
            if library.isEmpty {
                EmptyGalleryView(location: library.location, onSurpriseMe: create.surpriseMe)
                    .padding(.top, WP.Space.section * 2)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: WP.Space.grid),
                                         count: 3),
                          spacing: WP.Space.grid) {
                    ForEach(library.items) { item in
                        GalleryTile(item: item, library: library, aspect: 16.0 / 10.0)
                            // The tile is the picture on Mac, so the veil goes here. Tiles are
                            // aspect-fitted to a fixed rect, so the displayed rect is the tile
                            // itself — no fitted-rect maths.
                            // The live refinement over the tile, so Mac sees it arrive too.
                            .overlay {
                                if create.enhancingRecordID == item.id,
                                   let preview = create.enhancePreview {
                                    Image(platformImage: preview)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .clipped()
                                }
                            }
                            .overlay {
                                if create.enhancingRecordID == item.id,
                                   let progress = create.enhanceProgress, progress.total > 0 {
                                    EnhanceVeil(done: progress.done, total: progress.total,
                                                imageSize: nil)
                                }
                            }
                            .overlay {
                                if selection?.id == item.id {
                                    RoundedRectangle(cornerRadius: WP.Radius.tile, style: .continuous)
                                        .strokeBorder(WP.accent, lineWidth: 2)
                                }
                            }
                            .onTapGesture { selection = item }
                            .contextMenu { contextMenu(for: item) }
                    }
                }
                .padding(.horizontal, WP.Space.margin)
                .padding(.bottom, WP.Space.margin)
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for item: LibraryModel.Item) -> some View {
        Button("Set as Desktop") { actions.setDesktop(item.record, scope: .mainDisplay) }
        if actions.hasMultipleDisplays {
            Button("Set on All Displays") { actions.setDesktop(item.record, scope: .allDisplays) }
        }
        // The bundle's "Every Space on this display" row is deliberately absent: NSWorkspace
        // addresses an NSScreen, and there is no public API that addresses a Space. Shipping the row
        // would mean shipping a menu item that quietly does the same thing as the one above it.
        Divider()
        // The Mac's second Enhance door. There is no detail sheet here, so the context menu — the
        // surface this app already uses for per-item actions — is where it belongs.
        if EnhanceAvailability.isOffered {
            Button("Enhance") { create.enhance(item.record, library: library) }
                .disabled(!create.runner.isIdle)
        }
        Button("Use this prompt again") { onUsePrompt(item.record.prompt) }
        Button("Share…") { actions.share(item.record) }
        Divider()
        Button("Delete", role: .destructive) { Task { await library.delete(item) } }
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
