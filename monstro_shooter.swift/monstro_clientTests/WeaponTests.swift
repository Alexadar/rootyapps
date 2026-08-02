import Testing
import Foundation
@testable import monstro_client

@MainActor
struct WeaponTests {
    /// Build a Weapon with audio side-effects stubbed out.
    func makeWeapon(_ config: WeaponConfig) -> Weapon {
        let w = Weapon(config: config)
        w.reloadSoundHandler = {}   // don't trigger AudioManager during tests
        return w
    }

    @Test func startsFullyLoaded() {
        let w = makeWeapon(TestFixtures.weapon(magazineSize: 5))
        #expect(w.currentAmmo == 5)
        #expect(!w.isReloading)
    }

    // Note: fire() gates on `currentTime - lastShotTime >= shotDelay`, and lastShotTime
    // starts at 0, so the first shot must occur at a time >= shotDelay (in-game time is always large).

    @Test func firingConsumesOneRound() {
        let w = makeWeapon(TestFixtures.weapon(magazineSize: 5, bulletsPerShot: 1))
        let bullets = w.fire(at: 1.0, baseAngle: 0)
        #expect(bullets?.count == 1)
        #expect(w.currentAmmo == 4)
    }

    @Test func fireRateGatingBlocksRapidShots() {
        let w = makeWeapon(TestFixtures.weapon(magazineSize: 5, shotDelay: 0.1))
        _ = w.fire(at: 1.0, baseAngle: 0)
        #expect(w.fire(at: 1.05, baseAngle: 0) == nil)   // too soon
        #expect(w.currentAmmo == 4)
        #expect(w.fire(at: 1.1, baseAngle: 0) != nil)    // delay elapsed
        #expect(w.currentAmmo == 3)
    }

    @Test func shotgunFiresMultiplePellets() {
        let w = makeWeapon(TestFixtures.weapon(type: .shotgun, bulletsPerShot: 5))
        let bullets = w.fire(at: 1.0, baseAngle: 0)
        #expect(bullets?.count == 5)
    }

    @Test func emptyMagazineTriggersAutoReload() {
        let w = makeWeapon(TestFixtures.weapon(magazineSize: 3, shotDelay: 0.1))
        _ = w.fire(at: 1.0, baseAngle: 0)
        _ = w.fire(at: 1.5, baseAngle: 0)
        _ = w.fire(at: 2.0, baseAngle: 0)   // empties magazine -> auto reload
        #expect(w.currentAmmo == 0)
        #expect(w.isReloading)
        #expect(w.fire(at: 2.5, baseAngle: 0) == nil)   // can't fire while reloading
    }

    @Test func reloadProgressAndCompletion() {
        let w = makeWeapon(TestFixtures.weapon(magazineSize: 5, reloadTime: 2.0))
        w.forceReload(at: 0)
        #expect(w.isReloading)
        #expect(approxEqual(w.getReloadProgress(currentTime: 1.0), 0.5))
        w.update(currentTime: 2.0)   // reload completes
        #expect(!w.isReloading)
        #expect(w.currentAmmo == 5)
        #expect(approxEqual(w.getReloadProgress(currentTime: 2.0), 1.0))
    }

    @Test func restoreAmmoClampsToMagazine() {
        let w = makeWeapon(TestFixtures.weapon(magazineSize: 5))
        w.restoreAmmo(3)
        #expect(w.currentAmmo == 3)
        w.restoreAmmo(99)
        #expect(w.currentAmmo == 5)
        #expect(!w.isReloading)
    }
}
