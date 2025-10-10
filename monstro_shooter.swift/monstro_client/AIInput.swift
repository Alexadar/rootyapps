import Foundation
import CoreGraphics
import SpriteKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// AI-based input controller for animated main menu
/// Provides automated movement and shooting behavior for the main menu character.
class AIInput: InputController {
    private weak var scene: SKScene?
    private weak var playerNode: SKNode?
    private var monsters: [SKNode] = []

    // AI timing / state
    private var lastShootTime: TimeInterval = 0
    private var lastTargetChange: TimeInterval = 0
    private var moveTarget: CGPoint?
    private var spawnAttempted = false

    // Tunables
    private let targetChangeInterval: TimeInterval = 1.2
    private let shootCooldown: TimeInterval = 0.9
    private let patrolRadius: CGFloat = 140.0
    private let movementStrength: CGFloat = 1.0 // direction magnitude returned in -1..1 range

    init(scene: SKScene? = nil) {
        self.scene = scene
    }

    // MARK: - InputController

    /// Returns a direction vector in roughly -1..1 range.
    /// AI chooses to move toward nearest monster if present, otherwise picks a short-lived patrol target.
    func movementVector() -> CGVector {
        let now = CACurrentMediaTime()

        // Refresh target periodically
        if moveTarget == nil || now - lastTargetChange > targetChangeInterval {
            lastTargetChange = now
            if let nearest = nearestMonster() {
                // move toward a point offset from the monster so AI strafes a little
                let offset = CGVector(dx: CGFloat.random(in: -40...40), dy: CGFloat.random(in: -40...40))
                moveTarget = CGPoint(x: nearest.position.x + offset.dx, y: nearest.position.y + offset.dy)
            } else if let player = playerNode, let scene = scene {
                // pick a random point around the player within patrolRadius
                let angle = CGFloat(now.truncatingRemainder(dividingBy: 6.28))
                let r = patrolRadius * (0.6 + CGFloat.random(in: 0...0.4))
                moveTarget = CGPoint(x: player.position.x + cos(angle) * r, y: player.position.y + sin(angle) * r)
            } else if let scene = scene {
                // fallback: random point near center
                moveTarget = CGPoint(x: scene.size.width/2 + CGFloat.random(in: -100...100),
                                     y: scene.size.height/2 + CGFloat.random(in: -60...60))
            }
        }

        guard let target = moveTarget, let player = playerNode else {
            return CGVector(dx: 0, dy: 0)
        }

        // Compute direction from player to target
        let dx = target.x - player.position.x
        let dy = target.y - player.position.y
        let dist = sqrt(dx*dx + dy*dy)
        if dist < 8 {
            // reached target, pick a new one next tick
            moveTarget = nil
            return CGVector(dx: 0, dy: 0)
        }

        // Normalize direction to -1..1
        let ndx = CGFloat(dx / max(dist, 1.0)) * movementStrength
        let ndy = CGFloat(dy / max(dist, 1.0)) * movementStrength
        return CGVector(dx: ndx, dy: ndy)
    }

    /// Aim point for shooting. Prefer nearest monster position if exists.
    func aimPoint() -> CGPoint? {
        if let monster = nearestMonster() {
            return monster.position
        }
        // If no monsters, aim slightly ahead of player's facing (or center)
        if let player = playerNode {
            return CGPoint(x: player.position.x + 80, y: player.position.y)
        }
        return nil
    }

    /// Decide when to shoot. Shoot periodically when monsters are present.
    func isShooting() -> Bool {
        let now = CACurrentMediaTime()
        if now - lastShootTime < shootCooldown { return false }
        if monsters.isEmpty { return false }
        lastShootTime = now
        return true
    }

    // MARK: - Management

    func setPlayerNode(_ node: SKNode) {
        self.playerNode = node
    }

    func updateMonsters(_ newMonsters: [SKNode]) {
        self.monsters = newMonsters
    }

    func reset() {
        lastShootTime = 0
        lastTargetChange = 0
        moveTarget = nil
    }

    // MARK: - Helpers

    private func nearestMonster() -> SKNode? {
        guard let player = playerNode, !monsters.isEmpty else { return nil }
        var best: SKNode? = nil
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for m in monsters {
            let dx = m.position.x - player.position.x
            let dy = m.position.y - player.position.y
            let d = sqrt(dx*dx + dy*dy)
            if d < bestDistance {
                bestDistance = d
                best = m
            }
        }
        return best
    }
}
