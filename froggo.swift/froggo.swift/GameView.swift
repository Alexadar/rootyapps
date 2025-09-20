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
    var score = 0
    var gameCamera: SKCameraNode!
    
    // UI elements
    var scoreLabel: SKLabelNode!
    var tutorialLabel: SKLabelNode!
    
    // Bindings for SwiftUI integration
    var gameStateBinding: Binding<GameState>?
    var finalScoreBinding: Binding<Int>?
    
    // Constants
    let pitHeight: CGFloat = -500
    let initialSkyscrapers = 20
    
    override func didMove(to view: SKView) {
        setupScene()
        setupCamera()
        setupUI()
        setupGame()
    }
    
    private func setupScene() {
        backgroundColor = SKColor.cyan
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
    }
    
    private func updateUI() {
        scoreLabel.text = "\(score)"
    }
    
    func gameOver() {
        guard !isGameOver else { return }
        isGameOver = true
        
        // Stop frog physics
        frog.physicsBody?.velocity = CGVector.zero
        frog.physicsBody?.affectedByGravity = false
        
        // Update final score and transition to game over screen
        finalScoreBinding?.wrappedValue = score
        
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
