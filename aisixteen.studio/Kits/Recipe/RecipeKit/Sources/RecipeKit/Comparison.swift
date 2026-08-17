import Foundation

/// The comparison handle, as a value.
///
/// Board `1j` is explicit that comparison is the resting state and not a final step: it is
/// available in **every** phase, including while the pass is running. Keeping the whole thing in a
/// Foundation value means the announcements and the 10 % stepping are proved by `swift test`, and
/// the view is left with nothing but a drag gesture.
///
/// ### One element, not two
///
/// VoiceOver sees a single adjustable element — *"Comparison. Showing enhanced. Adjustable."* Not a
/// slider plus a button; not two images. Swipe up and down move the split in 10 % steps and
/// announce the new position; double-tap-and-hold speaks *"Showing original"* for as long as it is
/// held.
public struct Comparison: Sendable, Equatable {

    /// How much of the frame shows the enhanced image. `1` is fully enhanced (the resting state),
    /// `0` is fully original.
    public private(set) var revealed: Double

    /// True while press-and-hold (or the Mac's Space bar) is showing the original. Transient — it
    /// never persists into the recipe, and releasing restores `revealed` untouched.
    public var isHoldingOriginal: Bool

    /// The VoiceOver increment. 10 % is the handoff's number.
    public static let step = 0.1

    /// The split starts fully enhanced: the user pressed Enhance, so that is what they should see.
    public init(revealed: Double = 1, isHoldingOriginal: Bool = false) {
        self.revealed = Self.clamp(revealed)
        self.isHoldingOriginal = isHoldingOriginal
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value.isFinite ? value : 1, 0), 1)
    }

    public mutating func setRevealed(_ value: Double) {
        revealed = Self.clamp(value)
    }

    /// Rounded to whole steps so repeated swipes cannot accumulate a drift like 0.7000000000001,
    /// which would announce "70 percent" one moment and "70 percent" the next while comparing
    /// unequal.
    public mutating func increment() {
        revealed = Self.clamp(((revealed / Self.step).rounded() + 1) * Self.step)
    }

    public mutating func decrement() {
        revealed = Self.clamp(((revealed / Self.step).rounded() - 1) * Self.step)
    }

    /// What the screen actually shows, once the transient hold is taken into account.
    public var effectiveRevealed: Double { isHoldingOriginal ? 0 : revealed }

    public var isShowingOriginalFully: Bool { effectiveRevealed == 0 }
    public var isShowingEnhancedFully: Bool { effectiveRevealed == 1 }

    // MARK: Accessibility

    public var accessibilityLabel: String { "Comparison" }

    /// The three shapes from `1j`: the two ends are named, the middle is a percentage.
    public var accessibilityValue: String {
        if isHoldingOriginal { return Self.holdAnnouncement }
        if revealed == 0 { return "Showing original" }
        if revealed == 1 { return "Showing enhanced" }
        return "\(Int((revealed * 100).rounded())) percent enhanced"
    }

    /// Spoken while double-tap-and-hold is held.
    public static let holdAnnouncement = "Showing original"

    /// Spoken on release.
    public var releaseAnnouncement: String { accessibilityValue }

    public var accessibilityHint: String {
        "Swipe up or down to move the split. Double tap and hold to see the original."
    }

    /// The corner labels on the split (`1d`). Upper case in the design; the strings are here so the
    /// view spells nothing itself.
    public static let originalCaption = "ORIGINAL"
    public static let enhancedCaption = "ENHANCED"

    /// The press-and-hold affordance's label (`1d`, `1g`).
    public static let holdAffordance = "Hold for original"
    /// The Mac says which key, because there is nothing to press and hold on a trackpad.
    public static let macHoldAffordance = "Hold Space for original"
}

/// Hit-target geometry for the handle, from `1j`.
///
/// Written down because the visual grip and the touch target are deliberately different sizes, and
/// a view that uses one number for both either looks wrong or fails the 44 pt floor.
public enum ComparisonHandleMetrics {
    /// What the user sees.
    public static let gripDiameter: Double = 38
    /// What the user can hit. Above the 44 pt floor on purpose — the handle is dragged, not tapped.
    public static let targetDiameter: Double = 56
    /// The floor everything tappable in this app obeys.
    public static let minimumHitTarget: Double = 44

    public static var satisfiesMinimumTarget: Bool { targetDiameter >= minimumHitTarget }
}
