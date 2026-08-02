import Foundation

/// Pure combat arithmetic extracted from `Player.takeDamage`.
/// Ported from the old ActionScript armor formula so it can be unit-tested
/// without constructing a SpriteKit-backed `Player`.
enum CombatMath {
    /// Damage actually applied after armor.
    /// `actualDamage = max(incoming - defense, minDamage)` where `minDamage`
    /// is 0.4 on every 4th hit (to prevent a fully-armored player taking zero damage forever).
    /// - Parameter hitCount: the running hit counter AFTER it has been incremented for this hit.
    static func actualDamage(incoming: Double, defense: Double, hitCount: Int) -> Double {
        let minDamage = (hitCount % 4 == 0) ? 0.4 : 0.0
        return max(incoming - defense, minDamage)
    }
}
