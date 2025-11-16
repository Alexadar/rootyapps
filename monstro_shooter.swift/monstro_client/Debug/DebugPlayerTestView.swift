import SwiftUI
import SpriteKit

/// Debug view: Test player weapons against spawning monsters
struct DebugPlayerTestView: View {
    let onBack: () -> Void
    @State private var testScene: DebugPlayerTestScene?
    @State private var currentWeaponId: Int = 1
    @State private var currentExoId: Int = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let scene = testScene {
                SpriteView(scene: scene)
                    .ignoresSafeArea()
            }

            // Control overlay
            VStack {
                HStack {
                    DebugBackButton(action: onBack)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                Spacer()

                HStack(spacing: 15) {
                    // Weapon buttons
                    VStack(alignment: .leading, spacing: 10) {
                        Text("WEAPONS")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)

                        ForEach(WeaponManager.shared.getAllWeapons()) { weapon in
                            Button(action: {
                                currentWeaponId = weapon.id
                                testScene?.switchWeapon(config: weapon)
                            }) {
                                Text(weapon.getLocalizedName())
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 120, height: 35)
                                    .background(currentWeaponId == weapon.id ? Color.green : Color.gray.opacity(0.7))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer()

                    // Exoskeleton buttons
                    VStack(alignment: .trailing, spacing: 10) {
                        Text("EXOSKELETONS")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)

                        ForEach(ExoskeletonManager.shared.getAllExoskeletons()) { exo in
                            Button(action: {
                                currentExoId = exo.id
                                testScene?.switchExoskeleton(exo: exo)
                            }) {
                                Text(exo.getLocalizedName())
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 140, height: 35)
                                    .background(currentExoId == exo.id ? Color.blue : Color.gray.opacity(0.7))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            let scene = DebugPlayerTestScene(size: CGSize(width: 1024, height: 768))
            scene.scaleMode = .resizeFill
            testScene = scene

            #if os(macOS)
            NSApp.mainWindow?.acceptsMouseMovedEvents = true
            #endif
        }
    }
}

/// SpriteKit scene for player weapon testing
class DebugPlayerTestScene: SKScene {
    private var player: Player?
    private var monsters: [Monster] = []
    private var bullets: [SimpleBullet] = []
    private var lastUpdateTime: TimeInterval = 0
    private var lastShotTime: TimeInterval = 0
    private let maxMonsters = 5
    private let spawnYStart: CGFloat = 600
    private let spawnYEnd: CGFloat = 400

    private var currentWeaponConfig: WeaponConfig = .pistol
    private let monstersQueue = DispatchQueue(label: "com.monstro.monsters", attributes: .concurrent)

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 1.0)

        setupBackground()
        setupPlayer()
        spawnInitialMonsters()
    }

    private func setupBackground() {
        let groundTexture = SKTexture(imageNamed: "ground")
        groundTexture.filteringMode = .nearest

        let tileSize: CGFloat = 576
        let tilesX = Int(ceil(size.width / tileSize)) + 1
        let tilesY = Int(ceil(size.height / tileSize)) + 1

        for row in 0..<tilesY {
            for col in 0..<tilesX {
                let tile = SKSpriteNode(texture: groundTexture)
                tile.size = CGSize(width: tileSize, height: tileSize)
                tile.position = CGPoint(
                    x: CGFloat(col) * tileSize - size.width / 2,
                    y: CGFloat(row) * tileSize - size.height / 2
                )
                tile.zPosition = -100
                addChild(tile)
            }
        }
    }

    private func setupPlayer() {
        let playerPos = CGPoint(x: size.width / 2, y: 100)
        player = Player(initialPosition: playerPos)

        if let playerSprite = player?.sprite {
            addChild(playerSprite)
        }
    }

    private func spawnInitialMonsters() {
        for _ in 0..<maxMonsters {
            spawnMonster()
        }
    }

    private func spawnMonster() {
        var shouldSpawn = false
        monstersQueue.sync {
            shouldSpawn = monsters.count < maxMonsters
        }
        guard shouldSpawn else { return }

        // Random monster type
        let monsterTypes = GameConstants.MonsterType.allCases
        guard let randomType = monsterTypes.randomElement(),
              let config = MonsterRegistry.shared.getConfig(forID: randomType.rawValue) else {
            return
        }

        let randomX = CGFloat.random(in: 100...(size.width - 100))
        let randomY = CGFloat.random(in: spawnYEnd...spawnYStart)

        let monster = Monster(config: config)
        monster.setup(at: CGPoint(x: randomX, y: randomY), targetPosition: .zero)

        if let sprite = monster.sprite {
            addChild(sprite)
        }

        monstersQueue.async(flags: .barrier) { [weak self] in
            self?.monsters.append(monster)
        }
    }

    override func update(_ currentTime: TimeInterval) {
        let deltaTime = lastUpdateTime == 0 ? 0 : currentTime - lastUpdateTime
        lastUpdateTime = currentTime

        guard deltaTime > 0 else { return }

        // Update monsters
        var monstersSnapshot: [Monster] = []
        monstersQueue.sync {
            monstersSnapshot = monsters
        }

        if let playerPos = player?.sprite.position {
            for monster in monstersSnapshot {
                monster.update(deltaTime: deltaTime, playerPosition: playerPos, playerHitboxRadius: 20)
            }
        }

        // Remove dead monsters and respawn
        var deadMonsters: [Monster] = []
        monstersQueue.sync {
            deadMonsters = monsters.filter { $0.isDead }
        }

        for monster in deadMonsters {
            monster.sprite?.removeFromParent()
            monstersQueue.async(flags: .barrier) { [weak self] in
                self?.monsters.removeAll { $0 === monster }
            }
            spawnMonster()
        }

        // Update bullets
        for bullet in bullets {
            bullet.update(deltaTime: deltaTime)
        }

        bullets.removeAll { bullet in
            if bullet.isOutOfRange {
                bullet.sprite.removeFromParent()
                return true
            }
            return false
        }

        // Check bullet-monster collisions
        checkBulletCollisions()
    }

    private func checkBulletCollisions() {
        var monstersSnapshot: [Monster] = []
        monstersQueue.sync {
            monstersSnapshot = monsters
        }

        for bullet in bullets {
            for monster in monstersSnapshot {
                guard !monster.isDead, let monsterSprite = monster.sprite else { continue }

                let dx = bullet.sprite.position.x - monsterSprite.position.x
                let dy = bullet.sprite.position.y - monsterSprite.position.y
                let distance = hypot(dx, dy)

                if distance < (monster.boxSize.width / 2 + 10) {
                    monster.health -= CGFloat(currentWeaponConfig.damage)

                    if monster.health <= 0 {
                        monster.die()
                    }

                    bullet.hit()
                }
            }
        }

        bullets.removeAll { $0.isDead }
    }

    func switchWeapon(config: WeaponConfig) {
        currentWeaponConfig = config
    }

    func switchExoskeleton(exo: ExoskeletonConfig) {
        player?.applyExoskeleton(exo)
    }

    #if os(macOS)
    override func mouseDown(with event: NSEvent) {
        handleShoot(at: event.location(in: self))
    }
    #else
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first {
            handleShoot(at: touch.location(in: self))
        }
    }
    #endif

    private func handleShoot(at location: CGPoint) {
        guard let playerPos = player?.sprite.position else { return }

        let currentTime = Date().timeIntervalSince1970
        guard currentTime - lastShotTime >= currentWeaponConfig.shotDelay else { return }
        lastShotTime = currentTime

        let dx = location.x - playerPos.x
        let dy = location.y - playerPos.y
        let angle = atan2(dy, dx)

        // Create bullets
        for _ in 0..<currentWeaponConfig.bulletsPerShot {
            let deviation = CGFloat.random(in: -currentWeaponConfig.bulletDeviation...currentWeaponConfig.bulletDeviation)
            let bulletAngle = angle + deviation

            let bullet = SimpleBullet(
                position: playerPos,
                angle: bulletAngle,
                speed: currentWeaponConfig.bulletSpeed,
                range: currentWeaponConfig.shotRange
            )

            addChild(bullet.sprite)
            bullets.append(bullet)
        }

        // Sound handled elsewhere
    }
}

// MARK: - Simple Bullet for Debug
class SimpleBullet {
    let sprite: SKSpriteNode
    let speed: CGFloat
    let range: CGFloat
    private var distanceTraveled: CGFloat = 0
    private(set) var isDead = false
    private let velocityX: CGFloat
    private let velocityY: CGFloat

    var isOutOfRange: Bool {
        return distanceTraveled >= range
    }

    init(position: CGPoint, angle: CGFloat, speed: CGFloat, range: CGFloat) {
        self.speed = speed
        self.range = range
        self.velocityX = cos(angle) * speed
        self.velocityY = sin(angle) * speed

        sprite = SKSpriteNode(color: .yellow, size: CGSize(width: 6, height: 6))
        sprite.position = position
        sprite.zPosition = 5
    }

    func update(deltaTime: TimeInterval) {
        let dx = velocityX * CGFloat(deltaTime)
        let dy = velocityY * CGFloat(deltaTime)

        sprite.position.x += dx
        sprite.position.y += dy

        distanceTraveled += hypot(dx, dy)
    }

    func hit() {
        isDead = true
        sprite.removeFromParent()
    }
}
