import SwiftUI

/// Reel-only self-demo hook. When the `KERFCALC_DEMO` env equals `key`, cycle `binding` through
/// `values` on a timer so the hero recomputes *live* while a screen recording is running — giving the
/// macOS reel the same "alive" feel as the iOS `ReelTour` (which drives real taps via XCUITest).
/// No-op in normal use: if the env var is unset/mismatched the task returns immediately. This mirrors
/// the app's other reel launch hooks (`KERFCALC_TAB` / `KERFCALC_TOOL`). See marketing/reels/README.md.
private struct ReelDemoModifier: ViewModifier {
    let key: String
    let binding: Binding<Double>
    let values: [Double]
    let stepSeconds: Double

    func body(content: Content) -> some View {
        content.task {
            guard LaunchOverride.matches("KERFCALC_DEMO", key), !values.isEmpty else { return }
            var i = 0
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.45)) { binding.wrappedValue = values[i % values.count] }
                i += 1
                try? await Task.sleep(nanoseconds: UInt64(stepSeconds * 1_000_000_000))
            }
        }
    }
}

extension View {
    /// Attach to a hero/readout so the reel can animate `binding` when `KERFCALC_DEMO == key`.
    func reelDemo(_ key: String, _ binding: Binding<Double>, _ values: [Double], step: Double = 0.8) -> some View {
        modifier(ReelDemoModifier(key: key, binding: binding, values: values, stepSeconds: step))
    }
}
