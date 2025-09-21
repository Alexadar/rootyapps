//
//  Fly.swift
//  froggo.swift
//
//  Created by Oleksandr Koreniuk on 19.09.2025.
//

import SpriteKit

class Fly: SKSpriteNode {
    private var isFlying = false
    private var spawnTimer: Timer?
    private let spawnTime: TimeInterval = 60.0 // Match Unity spawn every 60 seconds
    private let flySpeed: CGFloat = 2.0
    private let hidePosition = CGPoint(x: -1000, y: 1000)
    
    // Animation sprites
    private let fly1Texture: SKTexture
    private let fly2Texture: SKTexture
    private var animationTimer: Timer?
    
    weak var gameScene: GameScene?
    
    init() {
        // Create simple colored textures for animation
    // Match Unity asset names
    fly1Texture = SKTexture(imageNamed: "fly_1")
    fly2Texture = SKTexture(imageNamed: "fly_2")
        
        super.init(texture: fly1Texture, color: .black, size: CGSize(width: 15, height: 15))
        
        position = hidePosition
        setupPhysics()
        startSpawnTimer()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupPhysics() {
        physicsBody = SKPhysicsBody(rectangleOf: size)
        physicsBody?.categoryBitMask = PhysicsCategory.fly
        physicsBody?.contactTestBitMask = PhysicsCategory.frog
        physicsBody?.collisionBitMask = 0 // Flies don't collide with anything
        physicsBody?.isDynamic = false
        physicsBody?.affectedByGravity = false
    }
    
    private func startSpawnTimer() {
        spawnTimer = Timer.scheduledTimer(withTimeInterval: spawnTime, repeats: true) { [weak self] _ in
            self?.spawn()
        }
    }
    
    private func spawn() {
        guard !isFlying, let gameScene = gameScene else { return }
        
        print("Fly spawned")
        
    // Get screen dimensions relative to scene
    let screenWidth: CGFloat = gameScene.size.width
    let screenHeight: CGFloat = gameScene.size.height
        
        // Spawn fly to the left of the frog
        let frogPosition = gameScene.frog.position
        let positionX = frogPosition.x - screenWidth / 2
    let positionY = frogPosition.y + (screenHeight - frogPosition.y) * CGFloat.random(in: 0.1...0.45)
        
        position = CGPoint(x: positionX, y: positionY)
        isFlying = true
        
        startAnimation()
        
        // Play buzzing sound (placeholder)
        print("Fly buzzing...")
    }
    
    private func startAnimation() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.texture = self.texture == self.fly1Texture ? self.fly2Texture : self.fly1Texture
        }
    }
    
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
    
    func update() {
        guard isFlying, let gameScene = gameScene else { return }
        
        // Move fly to the right with random vertical movement
        let randomY = CGFloat.random(in: -2...2)
        position = CGPoint(x: position.x + flySpeed, y: position.y + randomY)
        
        // Check if fly has moved off screen
        let frogPosition = gameScene.frog.position
    let screenWidth: CGFloat = gameScene.size.width
        
        if position.x > frogPosition.x + screenWidth {
            die()
        }
    }
    
    func die() {
        guard isFlying else { return }
        
        print("Fly died")
        position = hidePosition
        isFlying = false
        stopAnimation()
    }
    
    deinit {
        spawnTimer?.invalidate()
        animationTimer?.invalidate()
    }
}
