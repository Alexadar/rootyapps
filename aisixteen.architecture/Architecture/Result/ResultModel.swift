import Foundation
import Observation
import SwiftUI

/// The comparison's state, and the gesture arbitration that goes with it.
///
/// Pulled out of the view because it is the part with rules: the clamp, the flip threshold, the
/// peek timing, and the VoiceOver value. All of it is testable without a gesture.
@MainActor
@Observable
final class ResultModel {

    /// 0 = fully "after", 1 = fully "before". Clamped so neither side ever fully disappears —
    /// a comparison with nothing to compare is a picture.
    private(set) var wipe: CGFloat = 0.55
    /// Hold-to-peek: the original, temporarily, at full width.
    private(set) var isPeeking = false

    /// Where the drag started, so a flip can be told from a wipe.
    private var dragOrigin: CGFloat?
    private var dragStartedAt: Date?
    private var didMove = false
    private var peekTask: Task<Void, Never>?
    private var wipeBeforePeek: CGFloat = 0.55

    static let minimum: CGFloat = 0.02
    static let maximum: CGFloat = 0.98
    /// How far a touch must travel before it counts as a wipe rather than a tap.
    static let movementThreshold: CGFloat = 6
    /// Below this, and quick, it is a tap.
    static let tapThreshold: CGFloat = 10
    static let tapDuration: TimeInterval = 0.3
    static let peekDelay: TimeInterval = 0.25
    /// VoiceOver's step. 10% matches the design board.
    static let adjustStep: CGFloat = 0.1

    init(wipe: CGFloat = 0.55) {
        self.wipe = Self.clamp(wipe)
    }

    // ── what the view draws ──────────────────────────────────────────────────────────────────

    /// How much of the "after" image is showing.
    ///
    /// While peeking, none of it: the whole point of hold-to-peek is the original, uninterrupted.
    var revealedWidthFraction: CGFloat { isPeeking ? 0 : wipe }

    /// The announced value. Note the inversion — `wipe` is where the divider is, and what the user
    /// is told is how much of the AFTER they can see.
    var revealedPercent: Int { Int((wipe * 100).rounded()) }

    // ── one gesture, three behaviours ────────────────────────────────────────────────────────

    func dragChanged(locationX: CGFloat, translationX: CGFloat, width: CGFloat, reduceMotion: Bool) {
        guard width > 0 else { return }

        if dragOrigin == nil {
            dragOrigin = locationX
            dragStartedAt = Date()
            didMove = false
            wipeBeforePeek = wipe
            // A touch that has not moved yet might become a hold. The timer is cancelled the
            // moment it does move, so a wipe never turns into a peek halfway through.
            peekTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.peekDelay))
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.beginPeek() }
            }
        }

        if abs(translationX) > Self.movementThreshold {
            didMove = true
            cancelPeek()
            wipe = Self.clamp(locationX / width)
        }
    }

    func dragEnded(translationX: CGFloat, width: CGFloat, reduceMotion: Bool) {
        let elapsed = dragStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        let moved = abs(translationX)
        cancelPeek()

        if isPeeking {
            endPeek()
        } else if !didMove && moved < Self.tapThreshold && elapsed < Self.tapDuration {
            flip(reduceMotion: reduceMotion)
        }

        dragOrigin = nil
        dragStartedAt = nil
        didMove = false
    }

    /// Tap-to-flip: all the way to whichever end is further away.
    func flip(reduceMotion: Bool) {
        withAnimation(ARCMotion.morph(reduceMotion: reduceMotion)) {
            wipe = wipe < 0.5 ? Self.maximum : Self.minimum
        }
    }

    private func beginPeek() {
        guard !didMove else { return }
        wipeBeforePeek = wipe
        isPeeking = true
    }

    private func endPeek() {
        isPeeking = false
        // Restores EXACTLY where it was. A peek that nudges the divider makes the comparison
        // untrustworthy, which is the one thing it cannot be.
        wipe = wipeBeforePeek
    }

    private func cancelPeek() {
        peekTask?.cancel()
        peekTask = nil
    }

    // ── VoiceOver ────────────────────────────────────────────────────────────────────────────

    /// One adjustable element, 10% a step.
    func adjust(revealMore: Bool) {
        wipe = Self.clamp(wipe + (revealMore ? Self.adjustStep : -Self.adjustStep))
    }

    func set(_ value: CGFloat) { wipe = Self.clamp(value) }

    static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, minimum), maximum)
    }
}
