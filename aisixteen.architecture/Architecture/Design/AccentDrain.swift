import SwiftUI

/// "Accent terracotta #B4552D — **drains to neutral during generation**."
///
/// A rule the design handoff states in its token table and that nothing in the mockups
/// implements — `GeneratingView` actively tints its `ProgressView` with `DS.accent`, which is the
/// precise opposite.
///
/// The reason it matters: terracotta is the colour of *choice* in this app. It marks the selected
/// preset, the primary action, the thing you are deciding. While a render is running there is
/// nothing to decide — the user is waiting — so the screen goes quiet and the colour comes back
/// when there is something to do again. A progress bar in the accent shouts for three minutes at
/// somebody who has already made their decision.
private struct AccentDrainedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Published once, at the root, from the engine's "is any job live" state.
    var accentDrained: Bool {
        get { self[AccentDrainedKey.self] }
        set { self[AccentDrainedKey.self] = newValue }
    }
}

extension ARC {
    /// The accent, or what it drains to.
    ///
    /// Every accent use in the app goes through this. A raw `ARC.accent` in a view is a view that
    /// will not drain — same failure shape as a bare `.glassEffect`.
    static func accent(drained: Bool) -> Color {
        drained ? ARC.neutral : ARC.accent
    }
}

/// Reads the drain state so a view can tint with one call.
struct DrainableAccent: ViewModifier {
    @Environment(\.accentDrained) private var drained
    let apply: (Color) -> AnyView

    func body(content: Content) -> some View {
        apply(ARC.accent(drained: drained))
    }
}

extension View {
    /// Tint with the accent, draining while a render runs.
    func arcAccentTint() -> some View {
        modifier(AccentTint())
    }
}

private struct AccentTint: ViewModifier {
    @Environment(\.accentDrained) private var drained

    func body(content: Content) -> some View {
        content
            .tint(ARC.accent(drained: drained))
            .animation(.easeInOut(duration: 0.45), value: drained)
    }
}
