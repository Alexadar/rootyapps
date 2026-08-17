import SwiftUI

/// The two accessibility settings this design actually changes behaviour for.
///
/// Injectable as an environment value rather than read straight from
/// `@Environment(\.accessibilityReduceMotion)`, and that is deliberate: it is what makes
/// "Reduce Transparency on/off" and "Reduce Motion on/off" real UNIT-test axes instead of
/// simulator settings somebody has to remember to flip. The house rule is to test the state space,
/// and a setting you can only reach through Settings is a setting that gets tested once.
struct AccessibilityMode: Equatable, Sendable {
    var reduceMotion: Bool = false
    var reduceTransparency: Bool = false

    static let standard = AccessibilityMode()
    static let reducedTransparency = AccessibilityMode(reduceTransparency: true)
    static let both = AccessibilityMode(reduceMotion: true, reduceTransparency: true)
}

private struct AccessibilityModeKey: EnvironmentKey {
    static let defaultValue = AccessibilityMode.standard
}

extension EnvironmentValues {
    var arcAccessibility: AccessibilityMode {
        get { self[AccessibilityModeKey.self] }
        set { self[AccessibilityModeKey.self] = newValue }
    }
}

/// Reads the real system settings once, at the root, and publishes them as one value.
///
/// Applied in exactly one place. Every view downstream reads `\.arcAccessibility`, so a test can
/// substitute the whole thing with one `.environment(...)`.
struct AccessibilityModeReader: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .environment(\.arcAccessibility, resolved)
            .modifier(TypeSizeOverride())
    }

    /// The DEBUG-only override exists because a UI test cannot flip an accessibility setting
    /// without going through Settings, and a suite that depends on the device's global state is a
    /// suite that passes or fails for reasons that have nothing to do with the code.
    private var resolved: AccessibilityMode {
        switch LaunchOverride.value(LaunchOverride.accessibility) {
        case "rt": return AccessibilityMode(reduceMotion: reduceMotion, reduceTransparency: true)
        case "rm": return AccessibilityMode(reduceMotion: true, reduceTransparency: reduceTransparency)
        case "both": return .both
        default:
            return AccessibilityMode(reduceMotion: reduceMotion,
                                     reduceTransparency: reduceTransparency)
        }
    }
}

/// Forces Dynamic Type for the AX5 pass, same reasoning.
private struct TypeSizeOverride: ViewModifier {
    func body(content: Content) -> some View {
        if LaunchOverride.value(LaunchOverride.accessibility) == "ax5" {
            content.environment(\.dynamicTypeSize, .accessibility5)
        } else {
            content
        }
    }
}

/// Every animation in the app, with its Reduce Motion variant beside it.
///
/// Keeping the pair together is the point: a `withAnimation(ARC.morph)` scattered through the
/// views has no way to become a cross-fade, and the README's "Reduce Motion → morph becomes
/// cross-fade" quietly never happens.
enum ARCMotion {

    /// The capsule → frame morph. Spring response 0.8, damping 0.85, from the design bundle.
    static func morph(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.8, dampingFraction: 0.85)
    }

    /// "Cancel plays the morph in reverse."
    ///
    /// ⚠️ **DECLARED AND NOT WIRED.** This has no call site. The board asks for it and
    /// `RedesignGenerator.cancel()`'s doc comment repeats it, but cancelling currently animates
    /// with whatever the surrounding view already uses.
    ///
    /// Left in place rather than deleted because the behaviour is genuinely wanted, and marked
    /// rather than left quiet because a token that exists, is unit-tested for its properties, and
    /// is called by nothing reads as a finished feature to anyone scanning the file. It needs a
    /// placement decision — which view owns the reverse, and from which state — that belongs with
    /// the person who has the morph in front of them, not invented here.
    static func cancelReverse(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.55, dampingFraction: 0.9)
    }

    static func reveal(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.85)
    }

    /// The progress bar NEVER springs. A bar that overshoots its step count is telling the user
    /// something happened that did not.
    static let progressFill = Animation.linear(duration: 0.25)

    /// ⚠️ **DECLARED AND NOT WIRED**, same as `cancelReverse`.
    ///
    /// It pairs with `glassEffectID`, and this app currently has none: the segment's travelling
    /// pill uses `matchedGeometryEffect` instead, which does the same job for a non-glass shape.
    /// The one previous `glassEffectID` in the shells was the cause of the layout collapse and was
    /// removed, so adding this back is a deliberate change to a working control rather than a
    /// tidy-up — and not one to make blind.
    static func glassTransition(reduceMotion: Bool) -> GlassEffectTransition {
        reduceMotion ? .identity : .matchedGeometry
    }

    /// The milk veil's blur, quantised under Reduce Motion.
    ///
    /// The README asks for "intermediates as stepped stills (no live blur easing)". Rounding the
    /// blur to a few discrete values is what turns a continuously easing image into a sequence of
    /// stills without changing anything about what is drawn.
    static func veilBlur(atStep step: Int, totalSteps: Int, reduceMotion: Bool) -> CGFloat {
        guard totalSteps > 0 else { return ARC.Veil.blurEnd }
        let fraction = min(max(Double(step) / Double(totalSteps), 0), 1)
        let continuous = ARC.Veil.blurStart * (1 - fraction)
        guard reduceMotion else { return continuous }

        let steps = Double(ARC.Veil.reduceMotionSteps)
        let quantised = (continuous / ARC.Veil.blurStart * steps).rounded(.down) / steps
        return ARC.Veil.blurStart * quantised
    }
}
