import SwiftUI

/// Every animation in the app, and what Reduce Motion does to it.
///
/// The bundle (`1h`) is precise about the split, and the distinction it draws is the important part:
///
/// - **Removed** under Reduce Motion — geometry morphs, the tile's "forms in place" zoom, the
///   toast's slide, spring overshoot everywhere. These are the interface moving.
/// - **Kept** — the emerging-image preview and the progress fill. Those are *content changing*, not
///   the interface moving, and removing them would take away the one thing that makes a 20-second
///   wait bearable. The veil still lifts, in three discrete steps rather than continuously.
enum WPMotion {

    /// The morph. Spring response 0.8, damping 0.85 — the bundle's numbers, used for every stage of
    /// Create → progress → frame → result so it reads as one object rather than four.
    static func morph(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.8, dampingFraction: 0.85)
    }

    /// The final expansion to full-bleed, 0.5 s.
    static func reveal(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.85)
    }

    /// Which spring a morph stage change gets.
    ///
    /// Every stage used `morph`'s 0.8 response, which left `reveal` defined and never called — the
    /// last arrival, where the picture takes the whole screen, moved at the same pace as the small
    /// capsule-to-card changes before it. The bundle gives that one its own faster spring because it
    /// travels much further: at 0.8 the same distance reads as the screen sagging open.
    ///
    /// A free function of the destination rather than a lookup inside the view, so the pairing is
    /// assertable without rendering anything.
    static func stageChange(toResult: Bool, reduceMotion: Bool) -> Animation {
        toResult ? reveal(reduceMotion: reduceMotion) : morph(reduceMotion: reduceMotion)
    }

    /// Which animation the bottom shelf's slot change gets.
    ///
    /// A toast **fades** — it is a sentence appearing, not an object moving, and springing it gives
    /// weight to something that will be gone in two seconds. The resume card is an object and keeps
    /// the morph. `toastFade` was declared for exactly this and never used, so both went through the
    /// spring.
    static func shelfChange(toToast: Bool, reduceMotion: Bool) -> Animation {
        toToast ? toastFade : morph(reduceMotion: reduceMotion)
    }

    /// The progress bar's width. Never springs — a bar that overshoots is reporting a step count it
    /// has not reached.
    static let progressFill = Animation.linear(duration: 0.25)

    /// Toasts fade after two seconds.
    static let toastFade = Animation.easeInOut(duration: 0.25)
    static let toastLifetime: Duration = .seconds(2)

    /// The glass transition for identified elements. Under Reduce Motion the identified geometry
    /// morph is replaced by a plain crossfade at the same final positions — the element still
    /// changes, it just does not travel.
    static func glassTransition(reduceMotion: Bool) -> GlassEffectTransition {
        reduceMotion ? .identity : .matchedGeometry
    }

    /// The veil's blur, in points, at a given step.
    ///
    /// Continuous normally. Under Reduce Motion it is quantised to three steps, so the picture still
    /// visibly clears without a continuously animating blur — which is motion, and is also the most
    /// expensive thing on screen.
    static func veilBlur(_ continuous: Double, initial: Double, reduceMotion: Bool) -> Double {
        guard reduceMotion, initial > 0 else { return continuous }
        let fraction = continuous / initial            // 1 at the start, 0 at the end
        switch fraction {
        case 0.66...:   return initial
        case 0.33..<0.66: return initial * 0.5
        case 0.01..<0.33: return initial * 0.2
        default:        return 0
        }
    }
}

/// Reads both accessibility settings at once.
///
/// They are needed together often enough — the morph consults motion, the plate consults
/// transparency, the veil consults both — that passing them individually invites one being
/// forgotten in a new view.
struct AccessibilityMode: Equatable {
    var reduceMotion: Bool
    var reduceTransparency: Bool

    static let standard = AccessibilityMode(reduceMotion: false, reduceTransparency: false)
}

private struct AccessibilityModeKey: EnvironmentKey {
    static let defaultValue = AccessibilityMode.standard
}

extension EnvironmentValues {
    var wpAccessibility: AccessibilityMode {
        get { self[AccessibilityModeKey.self] }
        set { self[AccessibilityModeKey.self] = newValue }
    }
}

/// Publishes the two settings into the environment as one value.
///
/// Applied once at the root. Views read `\.wpAccessibility` rather than the two system keys, which
/// is also what makes both directions of both settings testable — a test supplies the value, no
/// simulator setting required.
struct AccessibilityModeReader: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.environment(\.wpAccessibility,
                            AccessibilityMode(reduceMotion: reduceMotion,
                                              reduceTransparency: reduceTransparency))
    }
}
