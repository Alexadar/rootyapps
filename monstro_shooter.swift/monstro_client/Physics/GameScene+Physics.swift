import SpriteKit

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

            // Remove bullet
            if let bNode = bulletNode as? SKSpriteNode {
                // Find Bullet wrapper and remove
                if let idx = bullets.firstIndex(where: { $0.sprite == bNode }) {
                    let b = bullets[idx]
                    b.sprite.removeFromParent()
                    bullets.remove(at: idx)
                } else {
                    bNode.removeFromParent()
                }
            }

            // Find monster and trigger its death animation (do not remove immediately)
            if let monsterSprite = monsterNode as? SKSpriteNode {
                if let monsterIndex = monsters.firstIndex(where: { $0.sprite == monsterSprite }) {
                    monsters[monsterIndex].die()
                    monsters[monsterIndex].sprite.physicsBody?.categoryBitMask = 0
                    monsters[monsterIndex].sprite.physicsBody?.contactTestBitMask = 0
                    monsters[monsterIndex].sprite.physicsBody?.collisionBitMask = 0
                }
            }
        }

        // Player hits monster (game over condition)
        if (bodyA.categoryBitMask == PhysicsCategory.player && bodyB.categoryBitMask == PhysicsCategory.monster) ||
           (bodyA.categoryBitMask == PhysicsCategory.monster && bodyB.categoryBitMask == PhysicsCategory.player) {
            print("Player hit by monster!")
        }
    }
}
