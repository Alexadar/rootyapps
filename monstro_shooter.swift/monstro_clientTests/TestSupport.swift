import Foundation
import CoreGraphics
@testable import monstro_client

/// Approximate floating-point comparison for geometry/physics assertions.
func approxEqual(_ a: CGFloat, _ b: CGFloat, _ eps: CGFloat = 1e-6) -> Bool {
    abs(a - b) <= eps
}

func approxEqual(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool {
    abs(a - b) <= eps
}

enum TestFixtures {
    /// Build a WeaponConfig directly via its memberwise initializer (no bundle / Yams needed).
    @MainActor
    static func weapon(id: Int = 1,
                       type: WeaponType = .pistol,
                       damage: Double = 5.0,
                       shotRange: CGFloat = 1000,
                       magazineSize: Int = 5,
                       shotDelay: TimeInterval = 0.1,
                       reloadTime: TimeInterval = 2.0,
                       bulletsPerShot: Int = 1,
                       bulletDeviation: CGFloat = 0,
                       penetrationPower: Int = 1) -> WeaponConfig {
        WeaponConfig(
            id: id,
            name: "Test Weapon",
            type: type,
            nameLocalizations: nil,
            damage: damage,
            shotRange: shotRange,
            shotDelay: shotDelay,
            magazineSize: magazineSize,
            reloadTime: reloadTime,
            bulletsPerShot: bulletsPerShot,
            bulletSpeed: 800,
            bulletDeviation: bulletDeviation,
            maxDeviation: bulletDeviation,
            penetrationPower: penetrationPower,
            bulletStartScale: 0.3,
            bulletMaxScale: 1.0,
            bulletScaleGrowth: 0.05,
            bulletTextureName: "bullet_test",
            weaponSoundName: "weapon_test"
        )
    }
}
