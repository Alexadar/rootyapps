import SwiftUI
import GenerationKit
import LibraryKit
import TaskKit

/// What the app found left over from a previous launch.
///
/// Kept separate from `CreateModel` because it is answering a different question — *is there
/// unfinished work?* — and because it has to be answered once, at launch, before anything else has
/// started.
@MainActor
@Observable
final class ResumeModel {

    private(set) var offer: JobManifest?

    var hasOffer: Bool { offer != nil }

    /// Looks for interrupted work. Anything made by a model that is no longer installed is deleted
    /// rather than offered — resuming it could not produce the same picture, and an offer that
    /// cannot be honoured is worse than no offer.
    func look() {
        offer = JobStore.resumableJobs(matching: ModelCatalog.installedModels()).first
    }

    /// Hands the job back to Create. The prompt is put in the field first, because a resumed
    /// generation must show what it is making — and because `canStart` reads that field.
    func resume(_ manifest: JobManifest, create: CreateModel, library: LibraryModel?) {
        offer = nil
        switch manifest.kind {
        case .generate:
            create.prompt = manifest.prompt
            create.aspect = manifest.aspect
            create.start(saveTo: library, resuming: manifest)
        case .enhance(let recordID):
            // Enhance needs the library record the tiles belong to. If it has since been deleted the
            // job is meaningless, and quietly dropping it is the honest outcome.
            guard let record = library?.items.first(where: { $0.id == recordID })?.record else {
                JobStore(manifest: manifest).discard()
                return
            }
            create.enhance(record, library: library)
        }
    }

    func discard(_ manifest: JobManifest) {
        JobStore(manifest: manifest).discard()
        offer = nil
    }
}

/// The launch offer: *picked up where you left off*.
///
/// ### It never resumes on its own
///
/// Continuing costs battery, heat and a minute of foreground attention, and the user did not ask for
/// any of it *on this launch* — they may have opened the app to look at the gallery. An app that
/// starts a minute of Neural Engine work because it was launched has made a decision that was not
/// its to make.
///
/// ### It counts real units
///
/// "enhancing, 2 of 4 tiles", never a percentage and never a time. Both of those would be invented:
/// the app knows exactly how many tiles are on disk and cannot know how long the rest will take.
struct ResumeCard: View {
    @Environment(\.colorScheme) private var scheme

    let manifest: JobManifest
    var onResume: () -> Void
    var onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WP.Space.gap) {
            Text("Picked up where you left off")
                .wpFont(.cardHeading)
                .foregroundStyle(WP.ink(scheme))

            Text(manifest.prompt)
                .wpFont(.body)
                .foregroundStyle(WP.ink2(scheme))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(manifest.stage.summary)
                .wpFont(.caption, tabularNumbers: true)
                .foregroundStyle(WP.ink3(scheme))

            HStack(spacing: WP.Space.gap) {
                Button("Resume", action: onResume)
                    .buttonStyle(.glassProminent)
                    .tint(WP.accent)
                Button("Discard", action: onDiscard)
                    .buttonStyle(.glass)
            }
            .wpFont(.control)
            .padding(.top, WP.Space.hair)
        }
        .padding(WP.Space.margin)
        .frame(maxWidth: 360, alignment: .leading)
        .wpGlassCard(radius: WP.Radius.frame)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Unfinished work: \(manifest.prompt), \(manifest.stage.summary)")
    }
}

/// The collapsed form: one line, on the shelf.
///
/// ### Discard is behind a long press, and also behind an accessibility action
///
/// A destructive act should not sit one accidental tap from a control at habit height. But a long
/// press is **not reachable by VoiceOver**, so hiding Discard there alone would put it out of reach
/// of the users least able to recover from losing work. `.contextMenu` gives the long press (and a
/// right-click on Mac) and the explicit `.accessibilityAction` gives everyone else the same door.
struct ResumeChip: View {
    @Environment(\.colorScheme) private var scheme

    let manifest: JobManifest
    var onResume: () -> Void
    var onDiscard: () -> Void
    var onExpand: () -> Void

    var body: some View {
        HStack(spacing: WP.Space.gap) {
            // Tapping the body expands to the full card — where the prompt is, which is the thing a
            // one-line chip cannot show and the thing that decides whether the work is worth having.
            Button(action: onExpand) {
                Text("Unfinished — \(manifest.stage.chipSummary)")
                    .wpFont(.caption, tabularNumbers: true)
                    .foregroundStyle(WP.ink2(scheme))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

            Button("Resume", action: onResume)
                .buttonStyle(.plain)
                .wpFont(.control)
                .foregroundStyle(WP.accent)
        }
        .padding(.horizontal, WP.Space.grid)
        .frame(height: WP.minimumHitTarget)
        .wpGlassCapsule(.regular)
        .contextMenu {
            Button("Discard", role: .destructive, action: onDiscard)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Unfinished work: \(manifest.prompt), \(manifest.stage.summary)")
        .accessibilityAction(named: "Resume", onResume)
        .accessibilityAction(named: "Discard", onDiscard)
        .accessibilityAction(named: "Show details", onExpand)
    }
}
