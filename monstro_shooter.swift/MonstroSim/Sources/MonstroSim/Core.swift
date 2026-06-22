import Foundation

// MARK: - Seedable RNG (SplitMix64)
// Deterministic, reproducible randomness — essential for fair map comparison and
// repeatable training runs. The shipping game uses non-seedable global random;
// the sim threads this generator through everything instead.
public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: UInt64) { self.state = seed }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Simulation constants (mirrors GameConstants subset used by the sim)
public enum SimConstants {
    public static let tickDelta: Double = 1.0 / 30.0      // fixed sim timestep
    public static let playerSpeed: Double = 300.0
    public static let playerSize: Double = 60.0
    public static let playerMaxHealth: Int = 100
    public static let playerHitboxRadius: Double = (playerSize + playerSize) / 4.0  // 30
    public static let mapSize: Double = 12000.0           // matches convertMapConfigToLevel

    public static let bulletRadius: Double = 6.0          // sprite 12px -> radius 6
    public static let damageInterval: Double = 1.0        // periodic contact damage cadence
    public static let contactBuffer: Double = 5.0         // matches updateMonsterDamage

    // Off-screen spawn ring around the player (no viewport headless; nominal 1024x768 / 0.7 + 100).
    public static let spawnHalfWidth: Double = 830.0
    public static let spawnHalfHeight: Double = 650.0

    public static let spawnInterval: Double = 1.0         // monsters per wave staggered by this
}
