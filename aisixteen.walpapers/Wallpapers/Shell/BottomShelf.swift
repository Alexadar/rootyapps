import SwiftUI
import TaskKit

/// The one transient object above the segment control.
///
/// Two things want that slot — the resume offer and the toast — and they arrive independently.
/// Without an arbiter they stack, or worse, both animate into the same position and the last one to
/// render wins. So there is exactly one slot and a stated priority.
///
/// ### Why the resume offer moved here from the top of the screen
///
/// It was an overlay pinned to the top of the shell, where it competed with Create for the first
/// thing the eye lands on — and collided outright with the result screen's back chevron. The bottom
/// edge is where this app already puts things that are true for a moment: the toast lives there, and
/// the segment control gives them a shelf to sit on.
enum ShelfSlot: Equatable {
    case resume(JobManifest)
    case toast(String)

    /// Which of the two occupants this is, for callers choosing an animation. A property rather than
    /// a `case .toast = slot` at the call site, so "how a toast behaves" stays one decision.
    var isToast: Bool { if case .toast = self { return true }; return false }
}

enum ShelfPriority {
    /// **resume > toast.** Exactly one, or none.
    ///
    /// A free function over two optionals rather than a rule inside a view body, so the ordering can
    /// be asserted. The gate that used to live in `RootView.resumeOffer` — never offer a resume
    /// while something is running — moves in here with it, where it is checked rather than
    /// remembered.
    static func slot(resume: JobManifest?, toast: String?, isBusy: Bool) -> ShelfSlot? {
        // A resume offered mid-job is an offer the app cannot honour — the runner permits one piece
        // of model work, and the user is already using it.
        if let resume, !isBusy { return .resume(resume) }
        if let toast { return .toast(toast) }
        return nil
    }
}

struct BottomShelf: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.wpAccessibility) private var accessibility

    var create: CreateModel
    var resume: ResumeModel
    var library: LibraryModel

    @State private var expanded = false

    private var slot: ShelfSlot? {
        ShelfPriority.slot(resume: resume.offer,
                           toast: create.toast,
                           isBusy: create.isRunning || create.isEnhancing)
    }

    var body: some View {
        Group {
            switch slot {
            case .resume(let manifest):
                if expanded {
                    ResumeCard(manifest: manifest,
                               onResume: { start(manifest) },
                               onDiscard: { resume.discard(manifest) })
                } else {
                    ResumeChip(manifest: manifest,
                               onResume: { start(manifest) },
                               onDiscard: { resume.discard(manifest) },
                               onExpand: { expanded = true })
                }
            case .toast(let text):
                Text(text)
                    .wpFont(.caption)
                    .foregroundStyle(WP.ink(scheme))
                    .padding(.horizontal, WP.Space.grid)
                    .padding(.vertical, WP.Space.tight)
                    .wpGlassCapsule()
            case nil:
                EmptyView()
            }
        }
        // A toast fades; the resume card is an object and morphs. See `shelfChange`.
        .animation(WPMotion.shelfChange(toToast: slot?.isToast ?? false,
                                        reduceMotion: accessibility.reduceMotion),
                   value: slot)
        .transition(accessibility.reduceMotion
                    ? .opacity
                    : .move(edge: .bottom).combined(with: .opacity))
    }

    private func start(_ manifest: JobManifest) {
        expanded = false
        resume.resume(manifest, create: create, library: library)
    }
}
