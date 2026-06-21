import Foundation

// Sim entities + the game formulas (mirrors monstro_client/Logic + entity logic).
// Parity with the app is asserted in MonstroSimTests.

// MARK: - Formulas (mirror of the app's pure helpers)
public enum SimFormulas {
    /// CombatMath.actualDamage — armor with every-4th-hit 0.4 floor.
    public static func actualDamage(incoming: Double, defense: Double, hitCount: Int) -> Double {
        let minDamage = (hitCount % 4 == 0) ? 0.4 : 0.0
        return max(incoming - defense, minDamage)
    }

    /// MovementMath.clamp — keep a centered-anchor sprite inside the map.
    public static func clamp(_ p: Vec2, spriteSize: Double, mapSize: Double) -> Vec2 {
        let half = spriteSize / 2
        let lo = -mapSize / 2 + half
        let hi = mapSize / 2 - half
        return Vec2(min(max(p.x, lo), hi), min(max(p.y, lo), hi))
    }

    /// SpreadMath.deviationToAngle.
    public static func deviationToAngle(_ deviationPixels: Double, referenceDistance: Double = 500) -> Double {
        atan2(deviationPixels, referenceDistance)
    }

    /// SteeringMath.step — direct (bugs/walkers) or arc (birds) steering. Returns nil within stopDistance.
    public static func steer(from pos: Vec2, toward target: Vec2, velocity: Vec2,
                             speed: Double, turnRate: Double, useDirectSteering: Bool,
                             stopDistance: Double, dt: Double) -> (pos: Vec2, vel: Vec2)? {
        let d = target - pos
        let dist = d.length
        guard dist > stopDistance else { return nil }
        var v = velocity
        if useDirectSteering {
            v = Vec2(d.x / dist, d.y / dist) * speed
        } else {
            v = v + Vec2(turnRate * d.x / dist, turnRate * d.y / dist) * dt
            let total = v.length
            if total > 0 { v = v * (speed / total) }
        }
        return (pos + v * dt, v)
    }
}

// MARK: - Weapon state machine (mirror of Weapon.swift, audio removed)
public struct SimWeapon {
    public let cfg: WeaponCfg
    public private(set) var currentAmmo: Int
    public private(set) var isReloading = false
    private var lastShotTime: Double = 0
    private var reloadStartTime: Double = 0

    public init(_ cfg: WeaponCfg) { self.cfg = cfg; self.currentAmmo = cfg.magazineSize }

    public var reloadProgress: Double { isReloading ? min((/*now*/0), 1) : 1 }

    /// Returns true if a shot was fired this call (caller then spawns `bulletsPerShot` bullets).
    public mutating func fire(at t: Double) -> Bool {
        guard !isReloading else { return false }
        guard currentAmmo > 0 else { startReload(at: t); return false }
        guard t - lastShotTime >= cfg.shotDelay else { return false }
        currentAmmo -= 1
        lastShotTime = t
        if currentAmmo == 0 { startReload(at: t) }
        return true
    }

    public mutating func update(at t: Double) {
        if isReloading, t - reloadStartTime >= cfg.reloadTime {
            currentAmmo = cfg.magazineSize
            isReloading = false
        }
    }

    public func progress(at t: Double) -> Double {
        guard isReloading else { return 1 }
        return min((t - reloadStartTime) / cfg.reloadTime, 1)
    }

    private mutating func startReload(at t: Double) {
        guard !isReloading else { return }
        isReloading = true
        reloadStartTime = t
    }
}

// MARK: - Entities
public final class SimPlayer {
    public var pos: Vec2 = .zero
    public var heading: Double = 0          // radians, aim direction
    public var health: Int = SimConstants.playerMaxHealth
    public var hitCount: Int = 0
    public let defense: Double
    public let speed: Double
    public let hitboxRadius = SimConstants.playerHitboxRadius
    public var weapon: SimWeapon

    public init(weapon: WeaponCfg, exo: ExoCfg) {
        self.weapon = SimWeapon(weapon)
        self.defense = exo.defence
        self.speed = SimConstants.playerSpeed * exo.speed
    }

    public func takeDamage(_ dmg: Double) {
        hitCount += 1
        health -= Int(SimFormulas.actualDamage(incoming: dmg, defense: defense, hitCount: hitCount))
        if health < 0 { health = 0 }
    }
}

public final class SimMonster {
    public let typeID: Int
    public var pos: Vec2
    public var vel: Vec2 = .zero
    public let speed: Double
    public let boxWidth: Double
    public let damage: Double
    public var health: Double
    public let useDirectSteering: Bool
    public let turnRate: Double = 34
    public let rotationOffset: Double
    public var isDead = false

    public init(cfg: MonsterCfg, at pos: Vec2) {
        self.typeID = cfg.typeID
        self.pos = pos
        self.speed = cfg.speed
        self.boxWidth = cfg.boxWidth
        self.damage = cfg.damage
        self.health = cfg.health
        self.useDirectSteering = cfg.useDirectSteering
        self.rotationOffset = cfg.rotationOffset
    }

    public func update(dt: Double, playerPos: Vec2, playerRadius: Double) {
        let stop = playerRadius + boxWidth / 2
        if let r = SimFormulas.steer(from: pos, toward: playerPos, velocity: vel,
                                     speed: speed, turnRate: turnRate,
                                     useDirectSteering: useDirectSteering, stopDistance: stop, dt: dt) {
            pos = r.pos
            vel = r.vel
        }
    }
}

public struct SimBullet {
    public var pos: Vec2
    public var vel: Vec2
    public let damage: Double
    public let range: Double
    public let penetration: Int
    public var distanceTraveled: Double = 0
    public var hitCount: Int = 0

    public var isExpired: Bool { hitCount >= penetration || distanceTraveled >= range }
}
