import Foundation
import SpriteKit

// MARK: - Weapon Delegate
protocol WeaponDelegate: AnyObject {
    func weaponDidStartReload(_ weapon: Weapon)
    func weaponDidCompleteReload(_ weapon: Weapon)
    func weaponAmmoChanged(_ weapon: Weapon, current: Int, max: Int)
}

// MARK: - Weapon Class
class Weapon {
    let config: WeaponConfig
    weak var delegate: WeaponDelegate?

    private(set) var currentAmmo: Int
    private(set) var isReloading: Bool = false
    private var lastShotTime: TimeInterval = 0
    private var reloadStartTime: TimeInterval = 0

    init(config: WeaponConfig) {
        self.config = config
        self.currentAmmo = config.magazineSize
    }

    /// Attempt to fire weapon
    /// Returns array of BulletInfo if successful, nil if can't fire
    func fire(at currentTime: TimeInterval, baseAngle: CGFloat) -> [BulletInfo]? {
        // Check reload state
        guard !isReloading else { return nil }

        // Check ammo
        guard currentAmmo > 0 else {
            startReload(at: currentTime)
            return nil
        }

        // Check fire rate
        guard currentTime - lastShotTime >= config.shotDelay else {
            return nil
        }

        // Fire!
        currentAmmo -= 1
        lastShotTime = currentTime

        // Notify delegate
        delegate?.weaponAmmoChanged(self, current: currentAmmo, max: config.magazineSize)

        // Auto-reload on empty
        if currentAmmo == 0 {
            startReload(at: currentTime)
        }

        // Generate bullets with spread
        return generateBullets(baseAngle: baseAngle)
    }

    /// Update reload progress
    func update(currentTime: TimeInterval) {
        if isReloading {
            let elapsed = currentTime - reloadStartTime
            if elapsed >= config.reloadTime {
                completeReload()
            }
        }
    }

    /// Generate bullets with deviation
    private func generateBullets(baseAngle: CGFloat) -> [BulletInfo] {
        var bullets: [BulletInfo] = []

        for _ in 0..<config.bulletsPerShot {
            // Calculate deviation
            let deviation = CGFloat.random(in: -config.bulletDeviation...config.bulletDeviation)

            bullets.append(BulletInfo(
                damage: config.damage,
                speed: config.bulletSpeed,
                range: config.shotRange,
                deviation: deviation,
                penetration: config.penetrationPower,
                startScale: config.bulletStartScale,
                maxScale: config.bulletMaxScale,
                scaleGrowth: config.bulletScaleGrowth,
                textureName: config.bulletTextureName
            ))
        }

        return bullets
    }

    /// Start reload sequence
    private func startReload(at currentTime: TimeInterval) {
        guard !isReloading else { return }

        isReloading = true
        reloadStartTime = currentTime
        delegate?.weaponDidStartReload(self)

        // Play reload sound
        AudioManager.shared.playReloadSound()

        print("[\(config.name)] Reloading... (\(config.reloadTime)s)")
    }

    /// Complete reload
    private func completeReload() {
        currentAmmo = config.magazineSize
        isReloading = false
        delegate?.weaponDidCompleteReload(self)
        delegate?.weaponAmmoChanged(self, current: currentAmmo, max: config.magazineSize)
        print("[\(config.name)] Reload complete! Ammo: \(currentAmmo)/\(config.magazineSize)")
    }

    /// Force immediate reload
    func forceReload(at currentTime: TimeInterval) {
        guard !isReloading else { return }
        currentAmmo = 0
        startReload(at: currentTime)
    }

    /// Get reload progress (0.0 to 1.0)
    func getReloadProgress(currentTime: TimeInterval) -> CGFloat {
        guard isReloading else { return 1.0 }
        let elapsed = currentTime - reloadStartTime
        return min(CGFloat(elapsed / config.reloadTime), 1.0)
    }
}
