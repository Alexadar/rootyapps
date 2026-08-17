import SwiftUI

/// Every animation in the app, and what Reduce Motion does to it.
///
/// The handoff (`1k`) is precise about the split, and the distinction it draws is the important
/// part:
///
/// - **Removed** under Reduce Motion — the capsule morph, spring overshoot, the hold-original
///   dissolve. These are the interface moving.
/// - **Kept** — the image resolving under the veil, and the **split handle**, which is direct
///   manipulation and not animation at all. Removing the resolving preview would take away the one
///   thing that makes a twenty-second wait bearable.
enum STMotion {

    /// The morph. Spring response 0.8, damping 0.85 — the same numbers as the wallpaper app, used
    /// for every stage of Enhance → progress → Save so it reads as one object rather than three.
    static func morph(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.8, dampingFraction: 0.85)
    }

    /// The progress capsule's fill. Never springs — a bar that overshoots is reporting a step count
    /// it has not reached.
    static let progressFill = Animation.linear(duration: 0.25)

    /// Press-and-hold showing the original. Under Reduce Motion the swap is **instant** (`1k`).
    static func holdOriginal(reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0) : .easeOut(duration: 0.14)
    }

    /// The glass transition for identified elements. Under Reduce Motion the identified geometry
    /// morph becomes a plain crossfade at the same final positions — the element still changes, it
    /// just does not travel.
    static func glassTransition(reduceMotion: Bool) -> GlassEffectTransition {
        reduceMotion ? .identity : .matchedGeometry
    }

    /// The veil's blur, in points, at a given step.
    ///
    /// Continuous normally. Under Reduce Motion it steps down in three discrete jumps, so the
    /// picture still visibly clears — which is content changing — without a continuously animating
    /// blur, which is motion, and is also the most expensive thing on screen.
    static func veilBlur(_ continuous: Double, initial: Double, reduceMotion: Bool) -> Double {
        guard reduceMotion, initial > 0 else { return continuous }
        switch continuous / initial {
        case 0.66...:     return initial
        case 0.33..<0.66: return initial * 0.5
        case 0.01..<0.33: return initial * 0.2
        default:          return 0
        }
    }
}

/// Reads both accessibility settings at once.
///
/// They are needed together often enough — the morph consults motion, the plate consults
/// transparency, the veil consults both — that passing them individually invites one being forgotten
/// in a new view.
struct AccessibilityMode: Equatable {
    var reduceMotion: Bool
    var reduceTransparency: Bool

    static let standard = AccessibilityMode(reduceMotion: false, reduceTransparency: false)
}

private struct AccessibilityModeKey: EnvironmentKey {
    static let defaultValue = AccessibilityMode.standard
}

extension EnvironmentValues {
    var stAccessibility: AccessibilityMode {
        get { self[AccessibilityModeKey.self] }
        set { self[AccessibilityModeKey.self] = newValue }
    }
}

/// Publishes the two settings into the environment as one value.
///
/// Applied once at the root. Views read `\.stAccessibility` rather than the two system keys, which
/// is also what makes both directions of both settings testable — a test supplies the value, no
/// simulator setting required.
struct AccessibilityModeReader: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.environment(\.stAccessibility,
                            AccessibilityMode(reduceMotion: reduceMotion,
                                              reduceTransparency: reduceTransparency))
    }
}
