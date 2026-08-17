import SwiftUI
import GenerationKit
import LibraryKit

/// Everything a door needs to offer Enhance, built once rather than re-derived in a view body.
///
/// Enhance is reachable from the finished picture on Create and from the Gallery detail sheet, and
/// the design calls for *one treatment, both doors*. The availability predicate used to be written
/// twice — once in `CreateView` to decide whether to pass a closure, once again inside
/// `CreateModel.enhance` as a guard — which is two places for it to drift apart.
struct EnhanceAffordance {
    var record: WallpaperRecord
    var isRunning: Bool
    var progress: (done: Int, total: Int)?
    var error: String?
    var start: () -> Void
    var stop: () -> Void

    /// `nil` when Enhance cannot be offered at all: no picture, no ControlNet in the installed
    /// model, or no refiner. A door that shows a button it cannot honour is worse than one that
    /// shows nothing.
    @MainActor
    static func make(for record: WallpaperRecord?,
                     model: CreateModel,
                     library: LibraryModel?) -> EnhanceAffordance? {
        guard let record, EnhanceAvailability.isOffered else { return nil }
        let mine = model.enhancingRecordID == record.id
        return EnhanceAffordance(
            record: record,
            isRunning: mine && model.isEnhancing,
            progress: mine ? model.enhanceProgress : nil,
            error: mine ? model.enhanceError : nil,
            start: { model.enhance(record, library: library) },
            stop: { model.cancelEnhance() })
    }
}

/// Whether the installed model can refine at all.
///
/// Cached: it walks the model directory, and it is asked from view bodies that rebuild often. The
/// answer only changes when the model does, which cannot happen while the app is running.
enum EnhanceAvailability {
    private static var cached: Bool?

    static var isOffered: Bool {
        if let cached { return cached }
        let answer = evaluate(resources: CoreMLImageGenerator.bundledResourcesURL())
        cached = answer
        return answer
    }

    static func evaluate(resources: URL?) -> Bool {
        guard let resources else { return false }
        // Two questions, both required: does the *model* declare a ControlNet, and is the refiner's
        // pipeline actually present on disk? The declaration is what a future pack promises; the
        // files are what this build can run.
        guard ModelCatalog.installed(at: resources)?.hasControlNet == true else { return false }
        return TileRefiner.isAvailable(at: resources)
    }

    static func invalidate() { cached = nil }
}

/// The Enhance pill, its cost, its counter and its failure — the one treatment both doors show.
///
/// Carries **its own** `GlassEffectContainer` and a distinct `"enhance"` identity. The result frame
/// already spends `glassEffectID("job")`; reusing that id here would be a duplicate identity inside
/// one container, which degrades silently rather than failing. A separate id gets the morph the
/// design wants — the pill becomes the counter — without fighting the frame, and travels to the
/// Gallery sheet with no coupling to `JobMorph` at all.
struct EnhanceControls: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.wpAccessibility) private var accessibility
    @Namespace private var enhanceNamespace

    var affordance: EnhanceAffordance?

    var body: some View {
        if let affordance {
            GlassEffectContainer(spacing: WP.Space.tight) {
                VStack(spacing: WP.Space.tight) {
                    if let reason = affordance.error {
                        failure(reason)
                    } else if affordance.isRunning {
                        counter(affordance)
                    } else {
                        offer(affordance)
                    }
                }
            }
            .animation(WPMotion.morph(reduceMotion: accessibility.reduceMotion),
                       value: affordance.isRunning)
        }
    }

    private func offer(_ affordance: EnhanceAffordance) -> some View {
        VStack(spacing: WP.Space.hair) {
            Button(action: affordance.start) {
                Label("Enhance", systemImage: "wand.and.sparkles")
                    .wpFont(.control)
                    .foregroundStyle(WP.ink(scheme))
                    .padding(.horizontal, WP.Space.margin)
                    .frame(height: WP.pillHeight)
            }
            .buttonStyle(.plain)
            .wpGlassCapsule(.regular)
            .glassEffectID("enhance", in: enhanceNamespace)
            // Stated before the tap. A minute of the phone doing nothing else is not something to
            // discover afterwards.
            Text(EnhanceCopy.cost)
                .wpFont(.footnote)
                .foregroundStyle(WP.ink3(scheme))
        }
    }

    private func counter(_ affordance: EnhanceAffordance) -> some View {
        HStack(spacing: WP.Space.gap) {
            Text(countText(affordance))
                .wpFont(.control, tabularNumbers: true)
                .foregroundStyle(WP.ink(scheme))
            Button("Stop", action: affordance.stop)
                .buttonStyle(.plain)
                .wpFont(.control)
                .foregroundStyle(WP.ink2(scheme))
        }
        .padding(.horizontal, WP.Space.margin)
        .frame(height: WP.pillHeight)
        .wpGlassCapsule(.regular)
        .glassEffectID("enhance", in: enhanceNamespace)
        .accessibilityElement(children: .combine)
    }

    private func countText(_ affordance: EnhanceAffordance) -> String {
        guard let progress = affordance.progress, progress.total > 0 else { return "Adding detail…" }
        return "Adding detail… tile \(progress.done) of \(progress.total)"
    }

    private func failure(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: WP.Space.hair) {
            Text(reason)
                .wpFont(.caption)
                .foregroundStyle(WP.ink2(scheme))
            // The master is overwritten once, at the very end, so a refinement that died part-way
            // genuinely has not touched it — and that is the user's first fear.
            Text(EnhanceCopy.untouched)
                .wpFont(.caption)
                .foregroundStyle(WP.ink3(scheme))
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, WP.Space.margin)
        .padding(.vertical, WP.Space.gap)
        .wpGlassCard(radius: WP.Radius.plate)
    }
}

/// One primary capsule and at most two more controls; the rest go behind a `⋯`.
///
/// The row has room for three capsules. Enhance is worth one of them, so when it is present the
/// extras collapse into a menu. When it is absent the row looks exactly as it always has — a build
/// without a ControlNet is not quietly redesigned.
struct ResultActionBar: View {
    @Environment(\.colorScheme) private var scheme

    struct OverflowAction: Identifiable {
        var id: String { label }
        var label: String
        var symbol: String
        var isDestructive: Bool = false
        var action: () -> Void
    }

    var primaryTitle: String
    var onPrimary: () -> Void
    var collapsesExtras: Bool
    var overflow: [OverflowAction]

    var body: some View {
        HStack(spacing: WP.Space.gap) {
            Button(action: onPrimary) {
                Text(primaryTitle)
                    .wpFont(.button)
                    .foregroundStyle(GlassLabel.color(on: .tinted, scheme: scheme, enabled: true))
                    .frame(maxWidth: .infinity)
                    .frame(height: WP.smallCircleButton)
            }
            .buttonStyle(.plain)
            .wpGlassCapsule(.tinted)

            if collapsesExtras {
                Menu {
                    ForEach(overflow) { action in
                        Button(role: action.isDestructive ? .destructive : nil, action: action.action) {
                            Label(action.label, systemImage: action.symbol)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(WP.ink(scheme).opacity(0.8))
                        .frame(width: WP.smallCircleButton, height: WP.smallCircleButton)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .wpGlass(.regular, in: Circle())
                .accessibilityLabel("More actions")
            } else {
                ForEach(overflow) { action in
                    Button(action: action.action) {
                        Image(systemName: action.symbol)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(action.isDestructive
                                             ? WP.destructive(scheme) : WP.ink(scheme).opacity(0.8))
                            .frame(width: WP.smallCircleButton, height: WP.smallCircleButton)
                    }
                    .buttonStyle(.plain)
                    .wpGlass(.regular, in: Circle())
                    .accessibilityLabel(action.label)
                }
            }
        }
    }
}
