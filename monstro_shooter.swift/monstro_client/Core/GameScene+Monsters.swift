import SpriteKit

// MARK: - Monster Management
extension GameScene {

    func spawnMonster() {
        // Guard player — monsters need a target; skip spawning if player missing.
        guard let playerEntity = playerEntity else { return }

        let monster = Berserker()
        // Spawn at random edge of screen (scene uses centered anchor point, so coords are -size/2 to +size/2)
        let spawnSide = Int.random(in: 0...3)
        var spawnPosition: CGPoint

        switch spawnSide {
        case 0: // Top
            spawnPosition = CGPoint(x: CGFloat.random(in: -size.width/2...size.width/2), y: size.height/2 + 50)
        case 1: // Right
            spawnPosition = CGPoint(x: size.width/2 + 50, y: CGFloat.random(in: -size.height/2...size.height/2))
        case 2: // Bottom
            spawnPosition = CGPoint(x: CGFloat.random(in: -size.width/2...size.width/2), y: -size.height/2 - 50)
        default: // Left
            spawnPosition = CGPoint(x: -size.width/2 - 50, y: CGFloat.random(in: -size.height/2...size.height/2))
        }

        monster.setup(at: spawnPosition, targetPosition: playerEntity.sprite.position)
        addChild(monster.sprite)
        monsters.append(monster)
    }

    func updateMonsters(_ deltaTime: TimeInterval) {
        // Guard player presence before updating monsters that target the player.
        guard let playerEntity = playerEntity else { return }

        for monster in monsters {
            if debugRotationEnabled {
                monster.rotationOffset = debugRotationOffset
            }
            monster.update(deltaTime: deltaTime, playerPosition: playerEntity.sprite.position)
        }

        monsters.removeAll { monster in
            let distance = sqrt(pow(monster.sprite.position.x - playerEntity.sprite.position.x, 2) +
                               pow(monster.sprite.position.y - playerEntity.sprite.position.y, 2))
            if distance > 2000 {
                monster.sprite.removeFromParent()
                return true
            }
            return false
        }
    }
}
