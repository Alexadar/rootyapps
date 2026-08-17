import SwiftUI
import LibraryKit

/// One wallpaper, full-bleed, with the actions that belong to it.
///
/// The prompt is shown, quoted, with a *Use again* chip: it was stored precisely so it could be
/// reused, and a stored prompt the user cannot see is a stored prompt that might as well not exist.
struct WallpaperDetailView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    var item: LibraryModel.Item
    var library: LibraryModel
    /// Needed because `CreateModel` owns Enhance, its progress, its error, and the `JobRunner` that
    /// serialises every piece of model work. The Gallery is the second door onto the same job.
    var create: CreateModel
    var actions: any WallpaperActions
    var onUsePrompt: (String) -> Void

    @State private var image: PlatformImage?
    @State private var confirmingDelete = false

    var body: some View {
        ZStack {
            AmbientBackground(recent: image)

            if let image = livePreview ?? image {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(item.record.prompt)
                    // `.scaledToFit()` letterboxes, so the veil has to be told the picture's own
                    // size — drawn over the container it would cover the bars as well.
                    .overlay {
                        if let affordance, affordance.isRunning,
                           let progress = affordance.progress, progress.total > 0 {
                            EnhanceVeil(done: progress.done, total: progress.total,
                                        imageSize: image.wpPixelSize)
                        }
                    }
            }

            VStack {
                HStack {
                    backButton
                    Spacer()
                }
                Spacer()
                promptPlate
                EnhanceControls(affordance: affordance)
                actionRow
            }
            .padding(WP.Space.margin)
        }
        // Keyed on the file's modification date, not just the id: Enhance rewrites the master at
        // the same path, so an id-keyed task would never re-run and the detail view would keep
        // showing the picture from before the refinement.
        .task(id: Self.revision(of: item)) { image = await library.fullImage(for: item) }
        .confirmationDialog("Delete this wallpaper?",
                            isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await library.delete(item); dismiss() }
            }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("It will be removed from \(library.location?.captionSuffix ?? "this device").")
        }
    }

    /// The refinement as it stands, when it is *this* wallpaper being refined. Same live image the
    /// Create result shows — one treatment, both doors, including while it runs.
    private var livePreview: PlatformImage? {
        create.enhancingRecordID == item.id ? create.enhancePreview : nil
    }

    /// The same affordance the Create result builds — one factory, one treatment, both doors.
    private var affordance: EnhanceAffordance? {
        EnhanceAffordance.make(for: item.record, model: create, library: library)
    }

    /// A cheap fingerprint of the file's current contents: path plus modification time.
    private static func revision(of item: LibraryModel.Item) -> String {
        let modified = (try? item.record.imageURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(item.id)-\(modified)"
    }

    private var backButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.backward")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WP.ink(scheme))
                .frame(width: WP.minimumHitTarget, height: WP.minimumHitTarget)
        }
        .buttonStyle(.plain)
        .wpGlass(.regular, in: Circle())
        .accessibilityLabel("Back")
    }

    private var promptPlate: some View {
        HStack(alignment: .top, spacing: WP.Space.gap) {
            Text("“\(item.record.prompt)”")
                .wpFont(.caption)
                .foregroundStyle(WP.ink(scheme))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                onUsePrompt(item.record.prompt)
                dismiss()
            } label: {
                Text("Use again")
                    .wpFont(.caption)
                    .foregroundStyle(WP.ink(scheme))
                    .padding(.horizontal, WP.Space.gap)
                    .padding(.vertical, WP.Space.tight)
            }
            .buttonStyle(.plain)
            .wpGlassCapsule(.interactive, shadow: false)
        }
        .padding(WP.Space.grid)
        .wpGlassCard(radius: WP.Radius.plate)
    }

    private var actionRow: some View {
        // Three capsules is the cap. With Enhance present the share and delete circles collapse
        // behind a `⋯` — a deliberate discoverability trade for delete, which keeps its destructive
        // role and its confirmation dialog but loses its always-visible affordance.
        ResultActionBar(primaryTitle: actions.primaryActionTitle,
                        onPrimary: { Task { await actions.performPrimary(on: item.record) } },
                        collapsesExtras: affordance != nil,
                        overflow: [
                            .init(label: "Share", symbol: "square.and.arrow.up",
                                  action: { actions.share(item.record) }),
                            .init(label: "Delete", symbol: "trash", isDestructive: true,
                                  action: { confirmingDelete = true }),
                        ])
    }

    private func circle(_ symbol: String, label: String, tint: Color,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: WP.smallCircleButton, height: WP.smallCircleButton)
        }
        .buttonStyle(.plain)
        .wpGlass(.regular, in: Circle())
        .accessibilityLabel(label)
    }
}
