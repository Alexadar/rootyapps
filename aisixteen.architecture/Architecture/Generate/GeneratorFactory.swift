import Foundation
import RedesignKit

/// Where the model lands.
///
/// Three layers, the house pattern from the wallpaper app's `GeneratorFactory`:
///   1. the `Mock` build configuration (`ARCH_MOCK`), which will also exclude the asset pack;
///   2. a DEBUG-only environment override, for UI tests and for looking at a specific state;
///   3. the runtime presence of the model.
///
/// In THIS build there is no layer 3 — every path returns a mock, because no model exists yet.
/// The `#else` branch below is the entire integration: one line, one type, no UI change.
enum GeneratorFactory {

    /// - Parameter sink: where scripted interruptions are published. The same protocol the real
    ///   observers implement, so a scripted run drives exactly the code path a warm phone would.
    static func makeGenerator(sink: (any EnvironmentEventSink)? = nil) -> any RedesignGenerator {
        #if ARCH_MOCK
        return MockRedesignGenerator(speed: .device)
        #else
        let override = LaunchOverride.value(LaunchOverride.generator)

        // An interruption is not a generator — it is an event about the device. So a scripted
        // interruption WRAPS whichever generator was chosen rather than replacing it.
        let cues = cues(for: override)
        if !cues.isEmpty, let sink {
            return InterruptibleRedesignGenerator(base: MockRedesignGenerator(speed: .fast),
                                                  cues: cues,
                                                  sink: sink)
        }

        if let override, let scripted = scripted(override) {
            return scripted
        }

        // ── WHERE THE MODEL LANDS ─────────────────────────────────────────────────────────────
        // When the depth-conditioned Core ML pipeline is converted in ../aisixteen.models and
        // shipped as a Background Assets pack, this is the whole change:
        //
        //     if let resources = CoreMLRedesignGenerator.bundledResourcesURL() {
        //         return CoreMLRedesignGenerator(resourcesURL: resources)
        //     }
        //
        // Nothing above this line moves, and no view knows the difference.
        return MockRedesignGenerator(speed: .device)
        #endif
    }

    /// The depth estimator is the SECOND seam, and it is a model too — so it is mocked here on the
    /// same terms. Real depth from LiDAR, dual cameras or a photo's embedded disparity comes from
    /// Apple frameworks in `DepthSource` and does not pass through this factory at all.
    static func makeDepthEstimator() -> any DepthEstimator {
        // ── WHERE THE DEPTH MODEL LANDS ───────────────────────────────────────────────────────
        // Depth Anything V2 / MiDaS / Depth Pro, converted alongside the diffusion pipeline:
        //
        //     if let resources = CoreMLDepthEstimator.bundledResourcesURL() {
        //         return CoreMLDepthEstimator(resourcesURL: resources)
        //     }
        MockDepthEstimator()
    }

    /// The scripted states, for UI tests and for looking at one screen without waiting.
    private static func scripted(_ name: String) -> (any RedesignGenerator)? {
        switch name {
        case "mock": return MockRedesignGenerator(speed: .device)
        case "fast": return MockRedesignGenerator(speed: .fast)
        case "instant": return MockRedesignGenerator(speed: .instant)
        case "failing": return FailingRedesignGenerator(failAtStep: 11, error: .outOfMemory, speed: .fast)
        case "failing-early": return FailingRedesignGenerator(failAtStep: 2, error: .modelUnavailable, speed: .fast)
        case "no-resume": return RejectingCheckpointGenerator(speed: .fast)
        default: return nil
        }
    }

    /// Interruptions scripted onto whichever generator was chosen.
    ///
    /// Separate from `scripted` because an interruption is not a generator — it is an event about
    /// the device, published through the same sink the real observers use. That distinction is the
    /// reason the pause path is testable at all.
    static func cues(for override: String?) -> [InterruptibleRedesignGenerator.Cue] {
        switch override {
        case "thermal":
            return [.init(step: 6, interruption: .thermal(.elevated))]
        case "thermal-critical":
            return [.init(step: 6, interruption: .thermal(.critical))]
        case "call":
            return [.init(step: 6, interruption: .call(active: true)),
                    .init(step: 7, interruption: .call(active: false))]
        case "low-battery":
            return [.init(step: 6, interruption: .battery(BatterySnapshot(level: 0.08,
                                                                          isCharging: false,
                                                                          isUnknown: false,
                                                                          lowPowerMode: false)))]
        case "background":
            return [.init(step: 6, interruption: .scene(.suspended))]
        default:
            return []
        }
    }
}
