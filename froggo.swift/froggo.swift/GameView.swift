//
//  GameView.swift
//  froggo.swift
//
//  Created by Oleksandr Koreniuk on 19.09.2025.
//

import SwiftUI
import SpriteKit

struct GameView: View {
    @Binding var gameState: GameState
    @Binding var finalScore: Int
    
    var body: some View {
        SpriteView(scene: createGameScene())
            .ignoresSafeArea()
    }
    
    private func createGameScene() -> GameScene {
        let scene = GameScene()
        scene.size = CGSize(width: 800, height: 600)
        scene.scaleMode = .aspectFill
        scene.gameStateBinding = $gameState
        scene.finalScoreBinding = $finalScore
        return scene
    }
}

class GameScene: SKScene {
    // Game entities
    var frog: Frog!
    var fly: Fly!
    var gameManager: GameManager!
    var skyscrapers: [Skyscraper] = []
    
    // Game state
    var isGameOver = false
    var score = 0 {
        didSet { scoreLabel?.text = "\(score)" }
    }
    var gameCamera: SKCameraNode!
    
    // UI elements
    var scoreLabel: SKLabelNode!
    var tutorialLabel: SKLabelNode!
    private var bgNodes: [SKSpriteNode] = []
    
    // Bindings for SwiftUI integration
    var gameStateBinding: Binding<GameState>?
    var finalScoreBinding: Binding<Int>?
    
    // Constants
    let pitHeight: CGFloat = -500
    let initialSkyscrapers = 20
    private let bgTileWidth: CGFloat = 512 // approximate; will be set from texture size
    private let bgZ: CGFloat = -10
    
    override func didMove(to view: SKView) {
        setupScene()
        setupCamera()
        setupUI()
        setupBackground()
        setupGame()
    }
    
    private func setupScene() {
        backgroundColor = SKColor.black
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)
        physicsWorld.contactDelegate = self
    }
    
    private func setupCamera() {
        gameCamera = SKCameraNode()
        addChild(gameCamera)
        self.camera = gameCamera
    }
    
    private func setupUI() {
        // Score label
        scoreLabel = SKLabelNode(fontNamed: "Arial-Bold")
        scoreLabel.fontSize = 24
        scoreLabel.fontColor = .white
        scoreLabel.text = "0"
        scoreLabel.position = CGPoint(x: 0, y: 300)
        scoreLabel.zPosition = 100
        camera?.addChild(scoreLabel)
        
        // Tutorial label
        tutorialLabel = SKLabelNode(fontNamed: "Arial")
        tutorialLabel.fontSize = 16
        tutorialLabel.fontColor = .white
        tutorialLabel.text = "Slide down and sideways to help Freddy jump"
        tutorialLabel.position = CGPoint(x: 0, y: 250)
        tutorialLabel.zPosition = 100
        camera?.addChild(tutorialLabel)
    }

    private func setupBackground() {
        // Create horizontally tiling background similar to Unity scene
        let texture = SKTexture(imageNamed: "NightSky")
        guard texture.size() != .zero else { return }

        // Determine number of tiles to cover view width x2
        let worldHeight = size.height
        let scale = worldHeight / texture.size().height
        let tileWidth = texture.size().width * scale

        let tilesNeeded = Int(ceil((size.width * 2) / tileWidth)) + 2
        var totalWidth: CGFloat = 0

        for i in 0..<tilesNeeded {
            let node = SKSpriteNode(texture: texture)
            node.setScale(scale)
            node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            node.zPosition = bgZ
            addChild(node)
            bgNodes.append(node)
            node.position = CGPoint(x: CGFloat(i) * tileWidth - size.width, y: 0)
            totalWidth += tileWidth
        }
    }
    
    private func setupGame() {
        gameManager = GameManager(scene: self)
        
        // Create frog
        frog = Frog()
        frog.position = CGPoint(x: 0, y: 100)
        addChild(frog)
        
        // Add trajectory line to scene
        if let trajectoryLine = frog.trajectoryLine {
            addChild(trajectoryLine)
        }
        
        // Create fly
        fly = Fly()
        fly.gameScene = self
        addChild(fly)
        
        gameManager.generateInitialCity()
        focusOnFrog()
    }
    
    func focusOnFrog() {
        camera?.position = frog.position
        updateUI()
        updateBackground()
    }
    
    private func updateUI() {
        scoreLabel.text = "\(score)"
    }

    private func updateBackground() {
        guard let camera = camera, let first = bgNodes.first, let texture = first.texture else { return }
        let worldHeight = size.height
        let scale = worldHeight / texture.size().height
        let tileWidth = texture.size().width * scale

        // Keep backgrounds centered vertically on camera
        for node in bgNodes { node.position.y = camera.position.y }

        // Reposition nodes when camera moves right
        let leftEdge = camera.position.x - size.width / 2
        let rightEdge = camera.position.x + size.width / 2

        // If leftmost tile entirely left of view, move it to the right end
        if let firstNode = bgNodes.first, firstNode.position.x + tileWidth / 2 < leftEdge {
            if let lastNode = bgNodes.last {
                firstNode.position.x = lastNode.position.x + tileWidth
                bgNodes.removeFirst()
                bgNodes.append(firstNode)
            }
        }
    }
    
    func gameOver() {
        guard !isGameOver else { return }
        isGameOver = true
        
        // Stop frog physics
        frog.physicsBody?.velocity = CGVector.zero
        frog.physicsBody?.affectedByGravity = false
        
        // Update final score and transition to game over screen
        finalScoreBinding?.wrappedValue = score
    SoundManager.shared.playGameOverSound()
        
        // Show game over after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.gameStateBinding?.wrappedValue = .gameOver
        }
    }
    
    override func update(_ currentTime: TimeInterval) {
        // Check if frog fell below pit height
        if frog.position.y <= pitHeight && !isGameOver {
            gameOver()
        }
        
        // Update fly
        fly.update()
        
        // Focus camera on frog
        focusOnFrog()
    }
}

extension GameScene: SKPhysicsContactDelegate {
    func didBegin(_ contact: SKPhysicsContact) {
        let bodyA = contact.bodyA
        let bodyB = contact.bodyB
        
        // Handle frog-skyscraper collision
        if (bodyA.categoryBitMask == PhysicsCategory.frog && bodyB.categoryBitMask == PhysicsCategory.skyscraper) ||
           (bodyA.categoryBitMask == PhysicsCategory.skyscraper && bodyB.categoryBitMask == PhysicsCategory.frog) {
            
            let skyscraper = bodyA.categoryBitMask == PhysicsCategory.skyscraper ? bodyA.node as! Skyscraper : bodyB.node as! Skyscraper
            frog.landOnSkyscraper(skyscraper)
            gameManager.onProgress(skyscraper.index)
        }
        
        // Handle frog-fly collision
        if (bodyA.categoryBitMask == PhysicsCategory.frog && bodyB.categoryBitMask == PhysicsCategory.fly) ||
           (bodyA.categoryBitMask == PhysicsCategory.fly && bodyB.categoryBitMask == PhysicsCategory.frog) {
            
            fly.die()
            frog.eatFly()
        }
    }
}

struct PhysicsCategory {
    static let frog: UInt32 = 1
    static let skyscraper: UInt32 = 2
    static let fly: UInt32 = 4
}
