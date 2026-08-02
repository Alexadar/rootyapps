//
//  Frog.swift
//  froggo.swift
//
//  Created by Oleksandr Koreniuk on 19.09.2025.
//

import SpriteKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum SwipeDirection {
    case up, down, left, right
}

class Frog: SKSpriteNode {
    // Drag mechanics
    private var dragStartPoint: CGPoint = .zero
    private var dragEndPoint: CGPoint = .zero
    private var isDragging = false
    var trajectoryLine: SKShapeNode?

    // Frog states
    private var isOnRoof = false
    private var flyEaten = false
    private var stabilityCheck = 0
    private var previousPosition: CGPoint = .zero

    // Reference to GameManager for parameters
    private weak var gameManager: GameManager?

    // Constants (tuned values)
    private let flyEatenMultiplier: CGFloat = 1.5
    private let stabilityChecks = 5

    // tvOS remote input tracking
    #if os(tvOS)
    private var remoteAimDirection: CGPoint = CGPoint(x: -1, y: 0) // Default: forward jump
    private let remoteAimStep: CGFloat = 20 // How much each swipe adjusts aim
    #endif
    
    // Sprites (using colored rectangles for now)
    private let idleTexture: SKTexture
    private let jumpTexture: SKTexture
    
    init(gameManager: GameManager) {
        // Use Unity-equivalent asset names (idle_frog, jump_frog)
        idleTexture = SKTexture(imageNamed: "idle_frog")
        jumpTexture = SKTexture(imageNamed: "jump_frog")
        self.gameManager = gameManager

        super.init(texture: idleTexture, color: .green, size: CGSize(width: 40, height: 40))

        setupPhysics()
        setupTrajectoryLine()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Note: SKSpriteNode doesn’t have didMove(to parent:), so we rely on GameScene to add trajectoryLine.
    
    private func setupPhysics() {
        physicsBody = SKPhysicsBody(rectangleOf: size)
        physicsBody?.categoryBitMask = PhysicsCategory.frog
        physicsBody?.contactTestBitMask = PhysicsCategory.skyscraper | PhysicsCategory.fly
        physicsBody?.collisionBitMask = PhysicsCategory.skyscraper
        physicsBody?.restitution = 0.2
        physicsBody?.friction = 0.8
        physicsBody?.allowsRotation = false
    }
    
    private func setupTrajectoryLine() {
        trajectoryLine = SKShapeNode()
        trajectoryLine?.strokeColor = .white
        trajectoryLine?.lineWidth = 3
        trajectoryLine?.alpha = 0.7
        trajectoryLine?.zPosition = 1000
        // Add to scene when available
        if let parent = self.parent, let line = trajectoryLine { parent.addChild(line) }
    }
    
    func update(gameOver: Bool) {
        if gameOver {
            isOnRoof = false
            return
        }
        checkIfOnRoof()
    }

    private func checkIfOnRoof() {
        guard let physicsBody = physicsBody else { return }

        if stabilityCheck == 0 {
            previousPosition = position
        }

        let delta = CGPoint(x: position.x - previousPosition.x, y: position.y - previousPosition.y)

        // Match Unity's tolerance: 0.5 units
        if abs(delta.x) < 0.5 && abs(delta.y) < 0.5 && abs(physicsBody.velocity.dx) < 10 && abs(physicsBody.velocity.dy) < 10 {
            stabilityCheck += 1
            if stabilityCheck >= stabilityChecks {
                stabilityCheck = stabilityChecks - 1
                if !isOnRoof {
                    texture = idleTexture
                    isOnRoof = true
                    SoundManager.shared.playLandSound()
                }
            }
        } else {
            stabilityCheck = 0
            if isOnRoof {
                texture = jumpTexture
                isOnRoof = false
            }
            // Clear line while in air
            hideTrajectoryLine()
        }
    }
    
    func landOnSkyscraper(_ skyscraper: Skyscraper) {
        // Match Unity's precise collision detection logic
        let frogBottom = position.y - size.height / 2
        let scraperTop = skyscraper.position.y + skyscraper.size.height / 2

        // Unity uses Math.Round to get delta and checks if it's between 0 and 1
        let delta = round(frogBottom) - round(scraperTop)

        if delta >= 0 && delta <= 1 {
            // Successfully landed on top of skyscraper
            // Don't immediately set isOnRoof or change texture - let checkIfOnRoof() handle it
            // This prevents flickering between jump/idle animations
            // The sound will be played by checkIfOnRoof() when frog is truly stable
        } else {
            // Hit the side, not the top
            isOnRoof = false
            texture = jumpTexture
        }
    }
    
    func eatFly() {
        flyEaten = true
        SoundManager.shared.playFlyEatenSound()
    }
    
    // MARK: - Touch/Mouse Handling (called from GameScene)

    #if os(macOS)
    func handleMouseDown(at location: CGPoint) {
        guard isOnRoof else { return }
        startDrag(at: location)
    }

    func handleMouseDragged(to location: CGPoint) {
        guard isDragging else { return }
        continueDrag(to: location)
    }

    func handleMouseUp() {
        guard isDragging else { return }
        stopDrag()
    }
    #endif

    #if !os(macOS) && !os(tvOS)
    // iOS and visionOS touch handling
    func handleTouchBegan(at location: CGPoint) {
        guard isOnRoof else { return }
        startDrag(at: location)
    }

    func handleTouchMoved(to location: CGPoint) {
        guard isDragging else { return }
        continueDrag(to: location)
    }

    func handleTouchEnded() {
        guard isDragging else { return }
        stopDrag()
    }
    #endif

    // MARK: - tvOS Remote Handling
    #if os(tvOS)
    func handleRemoteSwipe(direction: SwipeDirection) {
        guard isOnRoof else { return }

        // Adjust aim direction based on swipe
        switch direction {
        case .left:
            remoteAimDirection.x -= remoteAimStep
        case .right:
            remoteAimDirection.x += remoteAimStep
        case .up:
            remoteAimDirection.y += remoteAimStep
        case .down:
            remoteAimDirection.y -= remoteAimStep
        }

        // Update trajectory visualization
        updateRemoteTrajectory()
    }

    func handleRemoteJump() {
        guard isOnRoof else { return }

        // Use accumulated aim direction for jump
        dragStartPoint = position
        dragEndPoint = CGPoint(
            x: position.x + remoteAimDirection.x,
            y: position.y + remoteAimDirection.y
        )

        stopDrag()

        // Reset aim for next jump
        remoteAimDirection = CGPoint(x: -1, y: 0)
    }

    private func updateRemoteTrajectory() {
        guard let trajectoryLine = trajectoryLine, let gameManager = gameManager else { return }

        var direction = remoteAimDirection

        // Limit magnitude using GameManager's jumperLength
        let magnitude = sqrt(direction.x * direction.x + direction.y * direction.y)
        if magnitude > gameManager.jumperLength {
            let scale = gameManager.jumperLength / magnitude
            direction.x *= scale
            direction.y *= scale
        }

        // Create trajectory path
        let path = CGMutablePath()
        path.move(to: position)

        let endPoint = CGPoint(x: position.x - direction.x, y: position.y - direction.y)
        path.addLine(to: endPoint)

        trajectoryLine.path = path
    }
    #endif
    
    private func startDrag(at point: CGPoint) {
        dragStartPoint = point
        isDragging = true
    }
    
    private func continueDrag(to point: CGPoint) {
        dragEndPoint = point
        updateTrajectoryLine()
    }
    
    private func stopDrag() {
        isDragging = false
        hideTrajectoryLine()
        jump()
    }
    
    private func updateTrajectoryLine() {
        guard let trajectoryLine = trajectoryLine, let gameManager = gameManager else { return }

        var direction = CGPoint(x: dragEndPoint.x - dragStartPoint.x, y: dragEndPoint.y - dragStartPoint.y)

        // Only forward: in Unity, you drag backwards (left) to jump forward (right).
        // Clamp any rightward drag (positive x) to zero so it doesn't create backward force.
        if direction.x > 0 { direction.x = 0 }

        // Limit magnitude using GameManager's jumperLength
        let magnitude = sqrt(direction.x * direction.x + direction.y * direction.y)
        if magnitude > gameManager.jumperLength {
            let scale = gameManager.jumperLength / magnitude
            direction.x *= scale
            direction.y *= scale
        }

        // Create trajectory path
        let path = CGMutablePath()
        path.move(to: position)

        let endPoint = CGPoint(x: position.x - direction.x, y: position.y - direction.y)
        path.addLine(to: endPoint)

        trajectoryLine.path = path
    }
    
    private func hideTrajectoryLine() {
        trajectoryLine?.path = nil
    }
    
    private func jump() {
        guard let physicsBody = physicsBody, let gameManager = gameManager else { return }

        var direction = CGPoint(x: dragEndPoint.x - dragStartPoint.x, y: dragEndPoint.y - dragStartPoint.y)

        // Only forward: clamp positive x drag to zero
        if direction.x > 0 { direction.x = 0 }

        let magnitude = sqrt(direction.x * direction.x + direction.y * direction.y)
        let forceCoefficient = min(magnitude / gameManager.jumperLength, 1.0)

        // Normalize direction
        if magnitude > 0 {
            direction.x /= magnitude
            direction.y /= magnitude
        }

        // Apply jump force using GameManager's jumpForce
        let jumpMultiplier = flyEaten ? flyEatenMultiplier : 1.0
        let force = CGVector(
            dx: -direction.x * gameManager.jumpForce * forceCoefficient * jumpMultiplier,
            dy: -direction.y * gameManager.jumpForce * forceCoefficient * jumpMultiplier
        )

        physicsBody.applyImpulse(force)

        // Reset states
        flyEaten = false
        isOnRoof = false
        texture = jumpTexture

        // Play jump sound (placeholder)
        SoundManager.shared.playJumpSound()
    }
}
