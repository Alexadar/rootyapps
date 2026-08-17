import Foundation

#if os(iOS)
import CoreHaptics
import UIKit
#endif

/// Every physical beat gets a distinct haptic signature (the Apple-Design-Award pattern:
/// haptics as material, one signature per event class) — and ONE beat is reserved as the
/// strongest: the third card's reveal (Marvel Snap's lesson: save the big haptic for the
/// moment that carries the drama).
///
/// First CoreHaptics use in this repo. CHHapticEngine where available, transient-generator
/// fallback, no-op on macOS. Honors the settings toggle.
@MainActor
final class HapticsController {

    enum Beat {
        case lift          // card leaves the deck — light, sharp
        case flipApex      // face passes edge-on — mid, crisp
        case land          // snap to position — firm
        case heroReveal    // the third card — the one reserved heavy hit
        case shimmerTick   // subtle: entering the immersive viewer
    }

    var isEnabled = true

#if os(iOS)
    private var engine: CHHapticEngine?
    private lazy var impactLight = UIImpactFeedbackGenerator(style: .light)
    private lazy var impactRigid = UIImpactFeedbackGenerator(style: .rigid)
    private lazy var impactHeavy = UIImpactFeedbackGenerator(style: .heavy)

    func prepare() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
        try? engine?.start()
    }

    func play(_ beat: Beat) {
        guard isEnabled else { return }
        if let engine {
            let (intensity, sharpness): (Float, Float) = switch beat {
            case .lift: (0.45, 0.7)
            case .flipApex: (0.6, 0.9)
            case .land: (0.8, 0.5)
            case .heroReveal: (1.0, 0.3)
            case .shimmerTick: (0.25, 1.0)
            }
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ], relativeTime: 0)
            if beat == .heroReveal {
                // The hero hit is a double strike: a soft thump then the full-weight landing.
                let pre = CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8),
                ], relativeTime: 0)
                let main = CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3),
                ], relativeTime: 0.09)
                if let pattern = try? CHHapticPattern(events: [pre, main], parameters: []),
                   let player = try? engine.makePlayer(with: pattern) {
                    try? player.start(atTime: CHHapticTimeImmediate)
                    return
                }
            }
            if let pattern = try? CHHapticPattern(events: [event], parameters: []),
               let player = try? engine.makePlayer(with: pattern) {
                try? player.start(atTime: CHHapticTimeImmediate)
                return
            }
        }
        // Generator fallback (older hardware or engine failure).
        switch beat {
        case .lift, .shimmerTick: impactLight.impactOccurred(intensity: 0.6)
        case .flipApex: impactRigid.impactOccurred(intensity: 0.7)
        case .land: impactRigid.impactOccurred(intensity: 0.9)
        case .heroReveal: impactHeavy.impactOccurred(intensity: 1.0)
        }
    }
#else
    func prepare() {}
    func play(_ beat: Beat) {}
#endif
}
