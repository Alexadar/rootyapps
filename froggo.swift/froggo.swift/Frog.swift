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
    
    // Constants
    private let jumpPower: CGFloat = 600
    private let flyEatenMultiplier: CGFloat = 1.5
    private let jumpMagnitudeMax: CGFloat = 200
    private let stabilityChecks = 5
    
    // Sprites (using colored rectangles for now)
    private let idleTexture: SKTexture
    private let jumpTexture: SKTexture
    
    init() {
    // Use Unity-equivalent asset names (idle_frog, jump_frog)
    idleTexture = SKTexture(imageNamed: "idle_frog")
    jumpTexture = SKTexture(imageNamed: "jump_frog")
        
        super.init(texture: idleTexture, color: .green, size: CGSize(width: 40, height: 40))
        
        setupPhysics()
        setupTrajectoryLine()
        
        // Start stability checking
        let checkAction = SKAction.repeatForever(
            SKAction.sequence([
                SKAction.run(checkIfOnRoof),
                SKAction.wait(forDuration: 0.1)
            ])
        )
        run(checkAction)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
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
        trajectoryLine?.zPosition = 10
        // Will add to parent when parent is available
    }
    
    private func checkIfOnRoof() {
        guard let physicsBody = physicsBody else { return }
        
        if stabilityCheck == 0 {
            previousPosition = position
        }
        
        let delta = CGPoint(x: position.x - previousPosition.x, y: position.y - previousPosition.y)
        
        if abs(delta.x) < 5 && abs(delta.y) < 5 && abs(physicsBody.velocity.dx) < 10 && abs(physicsBody.velocity.dy) < 10 {
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
        }
    }
    
    func landOnSkyscraper(_ skyscraper: Skyscraper) {
        // Check if frog landed on top of skyscraper
        let frogBottom = position.y - size.height / 2
        let scraperTop = skyscraper.position.y + skyscraper.size.height / 2
        
        let delta = abs(frogBottom - scraperTop)
        
        if delta <= 10 { // Tolerance for landing on top
            isOnRoof = true
            texture = idleTexture
        }
    }
    
    func eatFly() {
        flyEaten = true
    }
    
    // MARK: - Touch/Mouse Handling
    
    #if os(macOS)
    override func mouseDown(with event: NSEvent) {
        guard isOnRoof else { return }
        
        let location = event.location(in: parent!)
        startDrag(at: location)
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        
        let location = event.location(in: parent!)
        continueDrag(to: location)
    }
    
    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        stopDrag()
    }
    #else
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isOnRoof, let touch = touches.first else { return }
        
        let location = touch.location(in: parent!)
        startDrag(at: location)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isDragging, let touch = touches.first else { return }
        
        let location = touch.location(in: parent!)
        continueDrag(to: location)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isDragging else { return }
        stopDrag()
    }
    #endif
    
    private func startDrag(at point: CGPoint) {
        dragStartPoint = point
        isDragging = true
        isUserInteractionEnabled = true
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
        guard let trajectoryLine = trajectoryLine else { return }
        
        var direction = CGPoint(x: dragEndPoint.x - dragStartPoint.x, y: dragEndPoint.y - dragStartPoint.y)
        
        // Only allow forward jumps (positive x direction)
        if direction.x < 0 {
            direction.x = 0
        }
        
        // Limit magnitude
        let magnitude = sqrt(direction.x * direction.x + direction.y * direction.y)
        if magnitude > jumpMagnitudeMax {
            let scale = jumpMagnitudeMax / magnitude
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
        guard let physicsBody = physicsBody else { return }
        
        var direction = CGPoint(x: dragEndPoint.x - dragStartPoint.x, y: dragEndPoint.y - dragStartPoint.y)
        
        // Only allow forward jumps
        if direction.x < 0 {
            direction.x = 0
        }
        
        let magnitude = sqrt(direction.x * direction.x + direction.y * direction.y)
        let forceCoefficient = min(magnitude / jumpMagnitudeMax, 1.0)
        
        // Normalize direction
        if magnitude > 0 {
            direction.x /= magnitude
            direction.y /= magnitude
        }
        
        // Apply jump force
        let jumpMultiplier = flyEaten ? flyEatenMultiplier : 1.0
        let force = CGVector(
            dx: -direction.x * jumpPower * forceCoefficient * jumpMultiplier,
            dy: -direction.y * jumpPower * forceCoefficient * jumpMultiplier
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
