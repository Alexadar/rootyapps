import Foundation

// MARK: - Action
// MultiDiscrete([9, 16, 2]) : move direction (0=idle + 8 compass), aim sector, shoot.
public struct SimAction {
    public var moveDir: Int   // 0..8
    public var aimDir: Int    // 0..15
    public var shoot: Bool
    public init(moveDir: Int = 0, aimDir: Int = 0, shoot: Bool = false) {
        self.moveDir = moveDir; self.aimDir = aimDir; self.shoot = shoot
    }
    public static let moveDirs = 9
    public static let aimDirs = 16
    public static let dims = [moveDirs, aimDirs, 2]

    static func moveVector(_ dir: Int) -> Vec2 {
        switch dir {
        case 1: return Vec2(0, 1)    // N
        case 2: return Vec2(1, 1)    // NE
        case 3: return Vec2(1, 0)    // E
        case 4: return Vec2(1, -1)   // SE
        case 5: return Vec2(0, -1)   // S
        case 6: return Vec2(-1, -1)  // SW
        case 7: return Vec2(-1, 0)   // W
        case 8: return Vec2(-1, 1)   // NW
        default: return .zero
        }
    }
    static func aimAngle(_ dir: Int) -> Double { Double(dir) / Double(aimDirs) * 2 * .pi }
}

public struct StepResult {
    public let observation: [Float]
    public let reward: Double
    public let terminated: Bool   // agent died or won (MDP terminal)
    public let truncated: Bool    // time limit
    public var done: Bool { terminated || truncated }
}

public struct EpisodeConfig {
    public var maxSeconds: Double
    public var nearestK: Int
    public init(maxSeconds: Double = 120, nearestK: Int = 8) {
        self.maxSeconds = maxSeconds; self.nearestK = nearestK
    }
}

// MARK: - Episode metrics (basis for difficulty + fun/playability scoring)
public struct EpisodeResult {
    public var survivalTime: Double = 0
    public var victory: Bool = false
    public var died: Bool = false
    public var kills: Int = 0
    public var expectedTotal: Int = 0
    public var damageTaken: Double = 0
    public var shotsFired: Int = 0
    public var hits: Int = 0
    public var peakMonsters: Int = 0
    public var pressureSamples: [Double] = []   // alive-monster count sampled per second
    public var totalReward: Double = 0

    public var accuracy: Double { shotsFired > 0 ? Double(hits) / Double(shotsFired) : 0 }
    public var clearFraction: Double { expectedTotal > 0 ? Double(kills) / Double(expectedTotal) : 0 }
}

// MARK: - World (the headless engine)
public final class World {
    public let data: GameData
    public let level: SimLevel
    public let config: EpisodeConfig

    public private(set) var player: SimPlayer
    public private(set) var monsters: [SimMonster] = []
    public private(set) var bullets: [SimBullet] = []
    public private(set) var elapsed: Double = 0
    public private(set) var killCount: Int = 0

    private var rng: SeededGenerator
    private let weaponCfg: WeaponCfg
    private let exoCfg: ExoCfg
    private var spawnedWaves: Set<Int> = []
    private var pendingSpawns: [(time: Double, typeID: Int)] = []
    private var touching: Set<ObjectIdentifier> = []
    private var lastDamageTime: Double = 0
    private var lastPressureSample: Double = -1

    public private(set) var result = EpisodeResult()

    public init(data: GameData, level: SimLevel, weaponID: Int, exoID: Int, seed: UInt64, config: EpisodeConfig = EpisodeConfig()) {
        self.data = data
        self.level = level
        self.config = config
        self.rng = SeededGenerator(seed: seed)
        self.weaponCfg = data.weapons[weaponID] ?? data.weapons.values.first!
        self.exoCfg = data.exoskeletons[exoID] ?? data.exoskeletons.values.first!
        self.player = SimPlayer(weapon: weaponCfg, exo: exoCfg)
        var r = EpisodeResult()
        r.expectedTotal = level.expectedTotal
        self.result = r
    }

    public func reset() -> [Float] {
        player = SimPlayer(weapon: weaponCfg, exo: exoCfg)
        monsters.removeAll(); bullets.removeAll()
        elapsed = 0; killCount = 0
        spawnedWaves.removeAll(); pendingSpawns.removeAll()
        touching.removeAll(); lastDamageTime = 0; lastPressureSample = -1
        var r = EpisodeResult(); r.expectedTotal = level.expectedTotal
        result = r
        return observe()
    }

    // MARK: Step
    public func step(_ action: SimAction) -> StepResult {
        let dt = SimConstants.tickDelta
        elapsed += dt
        var stepDamage = 0.0
        let prevKills = killCount

        processWaves()
        popSpawns()
        applyAction(action)
        updateBullets(dt: dt)
        for m in monsters where !m.isDead {
            m.update(dt: dt, playerPos: player.pos, playerRadius: player.hitboxRadius)
        }
        resolveBulletHits()
        stepDamage += applyContactDamage()

        monsters.removeAll { $0.isDead }
        result.peakMonsters = max(result.peakMonsters, monsters.count)
        samplefun()

        // Reward shaping: survival + kills - damage, tanh-bounded terminal bonus (see docs).
        let killsThisStep = killCount - prevKills
        var reward = 0.01 + 1.0 * Double(killsThisStep) - 0.05 * stepDamage

        let died = player.health <= 0
        let victory = killCount >= level.expectedTotal && level.expectedTotal > 0
        let truncated = elapsed >= min(config.maxSeconds, level.durationSeconds > 0 ? level.durationSeconds : config.maxSeconds)
        if died { reward -= 10 }
        if victory { reward += 10 }

        result.survivalTime = elapsed
        result.victory = victory
        result.died = died
        result.kills = killCount
        result.damageTaken += stepDamage
        result.totalReward += reward

        return StepResult(observation: observe(), reward: reward,
                          terminated: died || victory, truncated: truncated && !(died || victory))
    }

    // MARK: Spawning
    private func processWaves() {
        for (i, wave) in level.waves.enumerated() where !spawnedWaves.contains(i) {
            if elapsed >= wave.startTime {
                for k in 0..<wave.count {
                    let t = elapsed + Double(k) * SimConstants.spawnInterval
                    let typeID = wave.typeIDs.randomElement(using: &rng) ?? wave.typeIDs[0]
                    pendingSpawns.append((t, typeID))
                }
                spawnedWaves.insert(i)
            }
        }
    }

    private func popSpawns() {
        var remaining: [(time: Double, typeID: Int)] = []
        for s in pendingSpawns {
            if s.time <= elapsed { spawnMonster(typeID: s.typeID) } else { remaining.append(s) }
        }
        pendingSpawns = remaining
    }

    private func spawnMonster(typeID: Int) {
        guard let cfg = data.monsters[typeID] else { return }
        let hw = SimConstants.spawnHalfWidth, hh = SimConstants.spawnHalfHeight
        let side = Int.random(in: 0...3, using: &rng)
        let p = player.pos
        var pos: Vec2
        switch side {
        case 0: pos = Vec2(p.x + Double.random(in: -hw...hw, using: &rng), p.y + hh)
        case 1: pos = Vec2(p.x + hw, p.y + Double.random(in: -hh...hh, using: &rng))
        case 2: pos = Vec2(p.x + Double.random(in: -hw...hw, using: &rng), p.y - hh)
        default: pos = Vec2(p.x - hw, p.y + Double.random(in: -hh...hh, using: &rng))
        }
        monsters.append(SimMonster(cfg: cfg, at: pos))
    }

    // MARK: Action
    private func applyAction(_ action: SimAction) {
        let dt = SimConstants.tickDelta
        // Move (normalize + 0.75 diagonal, clamp to map — mirrors MovementMath).
        var mv = SimAction.moveVector(action.moveDir)
        let len = mv.length
        if len > 0 {
            mv = Vec2(mv.x / len, mv.y / len)
            let diagonal = abs(mv.x) > 0.1 && abs(mv.y) > 0.1
            let mult = diagonal ? 0.75 : 1.0
            let np = player.pos + Vec2(mv.x * player.speed * mult * dt, mv.y * player.speed * mult * dt)
            player.pos = SimFormulas.clamp(np, spriteSize: SimConstants.playerSize, mapSize: SimConstants.mapSize)
        }
        // Aim.
        player.heading = SimAction.aimAngle(action.aimDir)
        // Shoot.
        if action.shoot, player.weapon.fire(at: elapsed) {
            let n = player.weapon.cfg.bulletsPerShot
            let dev = SimFormulas.deviationToAngle(player.weapon.cfg.bulletDeviation)
            for _ in 0..<n {
                let spread = Double.random(in: -dev...dev, using: &rng)
                let a = player.heading + spread
                let vel = Vec2(cos(a), sin(a)) * player.weapon.cfg.bulletSpeed
                bullets.append(SimBullet(pos: player.pos, vel: vel,
                                         damage: player.weapon.cfg.damage,
                                         range: player.weapon.cfg.shotRange,
                                         penetration: player.weapon.cfg.penetrationPower))
                result.shotsFired += 1
            }
        }
        player.weapon.update(at: elapsed)
    }

    // MARK: Bullets
    private func updateBullets(dt: Double) {
        for i in bullets.indices {
            bullets[i].pos = bullets[i].pos + bullets[i].vel * dt
            bullets[i].distanceTraveled += bullets[i].vel.length * dt
        }
        bullets.removeAll { $0.isExpired }
    }

    private func resolveBulletHits() {
        for i in bullets.indices {
            if bullets[i].isExpired { continue }
            for m in monsters where !m.isDead {
                let hitRange = SimConstants.bulletRadius + m.boxWidth / 2
                if bullets[i].pos.distance(to: m.pos) <= hitRange {
                    m.health -= bullets[i].damage
                    bullets[i].hitCount += 1
                    result.hits += 1
                    if m.health <= 0 { m.isDead = true; killCount += 1 }
                    if bullets[i].isExpired { break }
                }
            }
        }
        bullets.removeAll { $0.isExpired }
    }

    // MARK: Contact damage (mirror of updateMonsterDamage)
    private func applyContactDamage() -> Double {
        let pr = player.hitboxRadius
        var current: Set<ObjectIdentifier> = []
        for m in monsters where !m.isDead {
            let range = pr + m.boxWidth / 2 + SimConstants.contactBuffer
            if player.pos.distance(to: m.pos) <= range { current.insert(ObjectIdentifier(m)) }
        }
        var dealt = 0.0
        let before = player.health

        // Immediate damage for newly-touching monsters.
        let newly = current.subtracting(touching)
        if !newly.isEmpty {
            var dmg = 0.0
            for m in monsters where !m.isDead && newly.contains(ObjectIdentifier(m)) { dmg += m.damage }
            if dmg > 0 { player.takeDamage(dmg) }
        }
        touching = current

        // Periodic damage for all touching.
        if !touching.isEmpty, elapsed - lastDamageTime >= SimConstants.damageInterval {
            lastDamageTime = elapsed
            var dmg = 0.0
            for m in monsters where !m.isDead && touching.contains(ObjectIdentifier(m)) { dmg += m.damage }
            if dmg > 0 { player.takeDamage(dmg) }
        }
        dealt = Double(before - player.health)
        return max(0, dealt)
    }

    private func samplefun() {
        let sec = floor(elapsed)
        if sec > lastPressureSample {
            lastPressureSample = sec
            result.pressureSamples.append(Double(monsters.count))
        }
    }

    // MARK: Observation (egocentric, K nearest monsters, fixed-size padded)
    public static func observationSize(nearestK: Int = 8) -> Int { 6 + nearestK * 7 }

    public func observe() -> [Float] {
        var o: [Float] = []
        o.append(Float(player.health) / Float(SimConstants.playerMaxHealth))
        o.append(Float(player.weapon.currentAmmo) / Float(max(1, player.weapon.cfg.magazineSize)))
        o.append(player.weapon.isReloading ? 1 : 0)
        o.append(Float(cos(player.heading)))
        o.append(Float(sin(player.heading)))
        o.append(Float(min(elapsed / max(1, config.maxSeconds), 1)))

        let nearest = monsters.filter { !$0.isDead }
            .sorted { $0.pos.distance(to: player.pos) < $1.pos.distance(to: player.pos) }
            .prefix(config.nearestK)
        for m in nearest {
            let rel = m.pos - player.pos
            o.append(1)
            o.append(Float(rel.x / 1000))
            o.append(Float(rel.y / 1000))
            o.append(Float(m.vel.x / 200))
            o.append(Float(m.vel.y / 200))
            o.append(Float(rel.length / 1000))
            o.append(Float(Double(m.typeID) / 24))
        }
        for _ in nearest.count..<config.nearestK { o.append(contentsOf: [Float](repeating: 0, count: 7)) }
        return o
    }
}
