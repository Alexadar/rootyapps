import SpriteKit
import QuartzCore

// MARK: - Physics Contact Delegate
extension GameScene: SKPhysicsContactDelegate {
    func didBegin(_ contact: SKPhysicsContact) {
        let bodyA = contact.bodyA
        let bodyB = contact.bodyB

        // Bullet hits monster
        if (bodyA.categoryBitMask == PhysicsCategory.bullet && bodyB.categoryBitMask == PhysicsCategory.monster) ||
           (bodyA.categoryBitMask == PhysicsCategory.monster && bodyB.categoryBitMask == PhysicsCategory.bullet) {

            let bulletNode = bodyA.categoryBitMask == PhysicsCategory.bullet ? bodyA.node : bodyB.node
            let monsterNode = bodyA.categoryBitMask == PhysicsCategory.monster ? bodyA.node : bodyB.node

            // Handle bullet penetration
            if let bNode = bulletNode as? SKSpriteNode {
                if let idx = bullets.firstIndex(where: { $0.sprite == bNode }) {
                    let bullet = bullets[idx]

                    // Check if bullet can penetrate
                    if !bullet.canPenetrate() {
                        // Hit limit reached, remove bullet
                        bullet.sprite.removeFromParent()
                        bullets.remove(at: idx)
                    }
                    // Otherwise bullet continues flying
                }
            }

            // Find monster and trigger its death animation (do not remove immediately)
            if let monsterSprite = monsterNode as? SKSpriteNode {
                if let monsterIndex = monsters.firstIndex(where: { $0.sprite == monsterSprite }) {
                    let monster = monsters[monsterIndex]
                    guard !monster.isDead else { return }  // Skip if already dead

                    monster.die()
                    monster.sprite.physicsBody?.categoryBitMask = 0
                    monster.sprite.physicsBody?.contactTestBitMask = 0
                    monster.sprite.physicsBody?.collisionBitMask = 0
                    killCount += 1  // Increment kill counter

                    // Track kill for tutorial
                    tutorialController?.recordKill(at: CACurrentMediaTime())
                }
            }
        }

        // Player-monster collision detection is handled via updateMonsterDamage() using distance checks
        // No need to apply damage here to avoid duplicate damage
    }
}
