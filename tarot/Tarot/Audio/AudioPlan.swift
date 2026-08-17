import Foundation

/// Every sound the game can make, named by its bundled resource. The mapping from kernel
/// events to sounds lives in AppModel (next to the haptics, which fire on the same edges);
/// what lives here is the pure, testable policy — what the mixer should be doing given the
/// toggles and the scene phase.
enum GameSound: String, CaseIterable {
    case lift = "sfx_lift"
    case flip = "sfx_flip"
    case land = "sfx_land"
    case hero = "sfx_hero"
    case shuffle = "sfx_shuffle"
    case tick = "sfx_tick"

    /// Per-sound trim into the sfx bus, so relative levels are data, not scattered calls.
    var gain: Float {
        switch self {
        case .lift: 0.5
        case .flip: 0.6
        case .land: 0.8
        case .hero: 0.9
        case .shuffle: 0.6
        case .tick: 0.35
        }
    }
}

enum AudioPlan {
    /// The music bed's one resting level. Fades always target this or silence.
    static let musicLevel: Double = 0.55

    /// Target music-mixer volume for a given world state. The bed is "always on" (owner) —
    /// meaning it never depends on screen; only the user's toggle and the app being active
    /// (backgrounding fades it out, returning fades it back in) gate it.
    static func targetMusicVolume(musicEnabled: Bool, isActive: Bool) -> Double {
        (musicEnabled && isActive) ? musicLevel : 0
    }
}
