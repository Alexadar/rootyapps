//  ContentView.swift
//  swinerpg
//
//  Rewritten as a lightweight 2D top-down emoji RPG.
//  - All visuals are emoji characters (🐷 player, 🐗 enemies, 🍎 items, 🌳 tiles).
//  - Controls: on-screen D-pad (taps for steps) + Attack button.
//  - Features: movement, attack, enemy AI, HP, pickups, simple open-world spawn.
//  - Single-file implementation (Game controller + SpriteKit scene) for quick setup.
//
//  Notes:
//  - Uses SpriteKit via SwiftUI's SpriteView.
//  - Designed for Swift 2025 toolchains / modern SwiftUI + SpriteKit.
//  - Tweak constants (speeds, spawn rates, sizes) as desired.

import SwiftUI
import SpriteKit
import Combine

// Shared controller between SwiftUI HUD and GameScene.
final class GameController: ObservableObject {
    static let shared = GameController()
    @Published var direction: CGVector = .zero    // Movement direction (-1..1)
    @Published var attackTriggered: Bool = false  // Toggle to trigger attack
    @Published var spawnTriggered: Bool = false   // Debug: spawn an enemy
    @Published var dodgeTriggered: Bool = false   // Future use

    private init() {}
    func triggerAttack() {
        attackTriggered = true
    }
    func consumeAttack() {
        attackTriggered = false
    }
    func tapMove(_ v: CGVector, duration: TimeInterval = 0.12) {
        direction = v
        // reset after a short step (discrete stepping for touch D-pad)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            if self?.direction == v { self?.direction = .zero }
        }
    }
}

// Simple game constants
enum G {
    static let worldSize = CGSize(width: 2048, height: 1536)
    static let tileEmoji = "🌿"
    static let playerEmoji = "🐷"
    static let enemyEmoji = "🐗"
    static let itemEmoji = "🍎"
    static let playerSpeed: CGFloat = 220      // points per second
    static let enemySpeed: CGFloat = 80
    static let attackRange: CGFloat = 120
    static let playerMaxHP = 10
}

// Lightweight model stored as node.userData values
extension SKNode {
    func setInt(_ key: String, _ value: Int) {
        if userData == nil { userData = NSMutableDictionary() }
        userData?[key] = value
    }
    func getInt(_ key: String) -> Int {
        (userData?[key] as? Int) ?? 0
    }
}

// Main SpriteKit Scene
final class GameScene: SKScene {
    let controller = GameController.shared
    var cancellables = Set<AnyCancellable>()

    // Game nodes
    var player: SKLabelNode!
    var hudLabel: SKLabelNode!
    var lastUpdateTime: TimeInterval = 0
    var enemies: [SKLabelNode] = []

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .aspectFill
        backgroundColor = .init(red: 0.9, green: 0.95, blue: 1.0, alpha: 1.0)

        setupWorld()
        setupPlayer()
        spawnInitialEnemies(count: 6)
        setupHUD()

        // Observe spawn trigger for debug spawning
        controller.$spawnTriggered
            .receive(on: RunLoop.main)
            .sink { [weak self] triggered in
                if triggered {
                    self?.spawnEnemy(at: nil)
                    self?.controller.spawnTriggered = false
                }
            }
            .store(in: &cancellables)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) not supported") }

    deinit {
        cancellables.forEach { $0.cancel() }
    }

    // MARK: - Setup
    func setupWorld() {
        // Create a simple emoji tile background grid
        let tileSize: CGFloat = 64
        let cols = Int(size.width / tileSize) + 4
        let rows = Int(size.height / tileSize) + 4
        let baseX = -size.width/2
        let baseY = -size.height/2
        for r in 0..<rows {
            for c in 0..<cols {
                let tile = SKLabelNode(text: G.tileEmoji)
                tile.fontSize = tileSize * 0.9
                tile.verticalAlignmentMode = .center
                tile.horizontalAlignmentMode = .center
                let x = baseX + CGFloat(c) * tileSize + (tileSize/2)
                let y = baseY + CGFloat(r) * tileSize + (tileSize/2)
                tile.position = CGPoint(x: x + CGFloat.random(in: -6...6), y: y + CGFloat.random(in: -6...6))
                tile.zPosition = -10
                tile.alpha = 0.95
                addChild(tile)
            }
        }

        // Add a few decorative trees as obstacles
        for _ in 0..<40 {
            let tree = SKLabelNode(text: "🌳")
            tree.fontSize = 56
            tree.position = CGPoint(x: CGFloat.random(in: -size.width/2...size.width/2),
                                    y: CGFloat.random(in: -size.height/2...size.height/2))
            tree.zPosition = -1
            tree.name = "obstacle"
            addChild(tree)
        }
    }

    func setupPlayer() {
        player = SKLabelNode(text: G.playerEmoji)
        player.fontSize = 60
        player.position = .zero
        player.zPosition = 10
        player.setInt("hp", G.playerMaxHP)
        addChild(player)
    }

    func setupHUD() {
        hudLabel = SKLabelNode(fontNamed: "Menlo")
        hudLabel.fontSize = 18
        hudLabel.fontColor = .black
        hudLabel.horizontalAlignmentMode = .left
        hudLabel.verticalAlignmentMode = .top
        hudLabel.position = CGPoint(x: -size.width/2 + 16, y: size.height/2 - 16)
        hudLabel.zPosition = 200
        addChild(hudLabel)
        updateHUD()
    }

    func spawnInitialEnemies(count: Int) {
        for _ in 0..<count { spawnEnemy(at: nil) }
    }

    // MARK: - Spawning
    func spawnEnemy(at point: CGPoint?) {
        let pos = point ?? CGPoint(
            x: CGFloat.random(in: -size.width/2...size.width/2),
            y: CGFloat.random(in: -size.height/2...size.height/2)
        )
        // Avoid spawning on player
        if hypot(pos.x - player.position.x, pos.y - player.position.y) < 140 {
            return spawnEnemy(at: nil)
        }
        let e = SKLabelNode(text: G.enemyEmoji)
        e.fontSize = 48
        e.position = pos
        e.zPosition = 5
        e.name = "enemy"
        e.setInt("hp", 3)
        addChild(e)
        enemies.append(e)
    }

    func spawnItem(at point: CGPoint) {
        let item = SKLabelNode(text: G.itemEmoji)
        item.fontSize = 34
        item.position = point
        item.zPosition = 6
        item.name = "item"
        addChild(item)

        // simple float animation then vanish
        let seq = SKAction.sequence([
            SKAction.scale(by: 1.2, duration: 0.25),
            SKAction.wait(forDuration: 8),
            SKAction.fadeOut(withDuration: 0.5),
            SKAction.removeFromParent()
        ])
        item.run(seq)
    }

    // MARK: - Game Loop
    override func update(_ currentTime: TimeInterval) {
        let dt: TimeInterval
        if lastUpdateTime == 0 { dt = 1.0/60.0 }
        else { dt = min(1.0/30.0, currentTime - lastUpdateTime) }
        lastUpdateTime = currentTime

        // Handle movement
        let dir = controller.direction
        if dir.dx != 0 || dir.dy != 0 {
            let movement = CGVector(dx: dir.dx * G.playerSpeed * CGFloat(dt),
                                    dy: dir.dy * G.playerSpeed * CGFloat(dt))
            player.position = CGPoint(x: player.position.x + movement.dx,
                                      y: player.position.y + movement.dy)
            // clamp to world bounds
            player.position.x = GameScene.clamp(player.position.x, -size.width/2 + 20, size.width/2 - 20)
            player.position.y = GameScene.clamp(player.position.y, -size.height/2 + 20, size.height/2 - 20)
        }

        // Enemies simple AI: move towards player
        for e in enemies {
            if e.parent == nil { continue }
            let toPlayer = CGVector(dx: player.position.x - e.position.x,
                                    dy: player.position.y - e.position.y)
            let dist = hypot(toPlayer.dx, toPlayer.dy)
            if dist > 8 {
                let nx = toPlayer.dx / dist
                let ny = toPlayer.dy / dist
                e.position.x += nx * G.enemySpeed * CGFloat(dt)
                e.position.y += ny * G.enemySpeed * CGFloat(dt)
            }

            // If enemy collides with player => damage player occasionally
            if dist < 36 {
                // damage with some chance per second
                if Int.random(in: 0..<100) < Int(30 * dt) {
                    hurtPlayer(1)
                }
            }
        }

        // Attack handling
        if controller.attackTriggered {
            performAttack()
            controller.consumeAttack()
        }

        // Clean dead enemies
        enemies = enemies.filter { $0.parent != nil }

        updateHUD()
    }

    // MARK: - Combat
    func performAttack() {
        // Visual attack: quick scale pulse for player
        let pulse = SKAction.sequence([SKAction.scale(to: 1.4, duration: 0.08),
                                       SKAction.scale(to: 1.0, duration: 0.12)])
        player.run(pulse)

        // Damage enemies in range
        let range = G.attackRange
        var killedPositions: [CGPoint] = []
        for e in enemies {
            guard e.parent != nil else { continue }
            let dist = hypot(e.position.x - player.position.x, e.position.y - player.position.y)
            if dist <= range {
                // damage
                var hp = e.getInt("hp")
                hp -= 1
                if hp <= 0 {
                    // enemy dies: explosion emoji then remove
                    let boom = SKLabelNode(text: "💥")
                    boom.fontSize = 42
                    boom.position = e.position
                    boom.zPosition = 50
                    addChild(boom)
                    let seq = SKAction.sequence([SKAction.scale(to: 1.6, duration: 0.12),
                                                 SKAction.fadeOut(withDuration: 0.25),
                                                 SKAction.removeFromParent()])
                    boom.run(seq)
                    killedPositions.append(e.position)
                    e.removeFromParent()
                } else {
                    e.setInt("hp", hp)
                    // show hurt flash
                    let shake = SKAction.sequence([
                        SKAction.rotate(byAngle: 0.08, duration: 0.04),
                        SKAction.rotate(byAngle: -0.16, duration: 0.06),
                        SKAction.rotate(byAngle: 0.08, duration: 0.04),
                        SKAction.run { e.zRotation = 0 }
                    ])
                    e.run(shake)
                }
            }
        }

        // spawn items at killed positions
        for p in killedPositions {
            spawnItem(at: p)
        }
    }

    // MARK: - Player HP
    func hurtPlayer(_ amount: Int) {
        var hp = player.getInt("hp")
        hp -= amount
        player.setInt("hp", hp)
        // flash red by swapping text to angry emoji momentarily
        let old = player.text
        player.text = "😡"
        player.run(SKAction.sequence([SKAction.wait(forDuration: 0.18),
                                      SKAction.run { [weak self] in self?.player.text = old }]))
        if hp <= 0 {
            gameOver()
        }
    }

    func healPlayer(_ amount: Int) {
        var hp = player.getInt("hp")
        hp = min(G.playerMaxHP, hp + amount)
        player.setInt("hp", hp)
    }

    func gameOver() {
        // Simple game over overlay
        let over = SKLabelNode(text: "GAME OVER 🐽")
        over.fontName = "Menlo-Bold"
        over.fontSize = 48
        over.fontColor = .red
        over.position = .zero
        over.zPosition = 999
        addChild(over)
        isPaused = true
    }

    // MARK: - Helpers
    func updateHUD() {
        let hp = player.getInt("hp")
        hudLabel.text = "HP: \(hp)/\(G.playerMaxHP)   Enemies: \(enemies.count)"
    }

    static func clamp<T: Comparable>(_ v: T, _ a: T, _ b: T) -> T {
        if v < a { return a }
        if v > b { return b }
        return v
    }
}

// Free function for convenience clamp usage in scene
func clamp<T: Comparable>(_ v: T, _ a: T, _ b: T) -> T {
    if v < a { return a }
    if v > b { return b }
    return v
}

// MARK: - SwiftUI View + Controls
struct ContentView: View {
    @StateObject var controller = GameController.shared
    let scene: GameScene

    init() {
        // Create a scene sized to a reasonable viewport; SpriteView will scale to device
        let s = GameScene(size: CGSize(width: 1024, height: 768))
        s.scaleMode = .aspectFill
        self.scene = s
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // SpriteKit scene
                SpriteView(scene: scene)
                    .ignoresSafeArea()
                    .frame(width: geo.size.width, height: geo.size.height)

                // HUD + Controls
                VStack {
                    Spacer()
                    HStack {
                        // D-Pad (left)
                        dpad
                            .padding(.leading, 20)
                            .padding(.bottom, 20)

                        Spacer()

                        VStack(spacing: 12) {
                            // Attack button
                            Button(action: {
                                controller.triggerAttack()
                            }, label: {
                                Text("⚔️")
                                    .font(.system(size: 36))
                                    .frame(width: 76, height: 76)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            })
                            .accessibilityLabel("Attack")

                            // Spawn enemy (debug)
                            Button(action: {
                                controller.spawnTriggered = true
                            }, label: {
                                Text("➕🐗")
                                    .font(.system(size: 18))
                                    .padding(8)
                                    .background(.thinMaterial)
                                    .cornerRadius(10)
                            })
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                    }
                }

                // Top-left mini instructions overlay
                VStack(alignment: .leading) {
                    Text("🐷 Swift Emoji RPG")
                        .font(.headline)
                    Text("Controls: Tap D-Pad to step, ⚔️ to attack. Defeat 🐗, collect 🍎.")
                        .font(.subheadline)
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding()
                .position(x: 170, y: 60)
            }
        }
    }

    // Discrete D-Pad: Taps move the player a short step (works on touch & mouse)
    var dpad: some View {
        VStack(spacing: 6) {
            Button(action: { controller.tapMove(CGVector(dx: 0, dy: 1)) }) {
                Text("⬆️").font(.system(size: 28)).frame(width: 56, height: 56).background(.thinMaterial).cornerRadius(8)
            }
            HStack(spacing: 6) {
                Button(action: { controller.tapMove(CGVector(dx: -1, dy: 0)) }) {
                    Text("⬅️").font(.system(size: 28)).frame(width: 56, height: 56).background(.thinMaterial).cornerRadius(8)
                }
                Button(action: { controller.tapMove(CGVector(dx: 0, dy: 0)) }) {
                    Text("◻️").font(.system(size: 22)).frame(width: 56, height: 56).background(.regularMaterial).cornerRadius(8)
                }
                Button(action: { controller.tapMove(CGVector(dx: 1, dy: 0)) }) {
                    Text("➡️").font(.system(size: 28)).frame(width: 56, height: 56).background(.thinMaterial).cornerRadius(8)
                }
            }
            Button(action: { controller.tapMove(CGVector(dx: 0, dy: -1)) }) {
                Text("⬇️").font(.system(size: 28)).frame(width: 56, height: 56).background(.thinMaterial).cornerRadius(8)
            }
        }
    }
}

// SwiftUI Preview
#Preview {
    ContentView()
}
