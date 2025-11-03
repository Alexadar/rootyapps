import SpriteKit

// MARK: - Monster Management
extension GameScene {

    /// Spawn a monster at the edge of the spawn box around the player
    func spawnMonster(monsterType: String = "Berserker") {
        // Guard player — monsters need a target; skip spawning if player missing.
        guard let playerEntity = playerEntity else { return }

        // Create monster based on type
        let monster: Monster
        switch monsterType {
        case "Berserker":
            monster = Berserker()
        default:
            monster = Berserker()  // Fallback to Berserker
        }

        // Spawn at random edge of spawn box (not screen edges!)
        // Spawn box follows the player but is bounded by map
        let playerPos = playerEntity.sprite.position
        let spawnBoxHalfWidth = currentSpawnBoxSize.width / 2
        let spawnBoxHalfHeight = currentSpawnBoxSize.height / 2

        let spawnSide = Int.random(in: 0...3)
        var spawnPosition: CGPoint

        switch spawnSide {
        case 0: // Top edge of spawn box
            spawnPosition = CGPoint(
                x: playerPos.x + CGFloat.random(in: -spawnBoxHalfWidth...spawnBoxHalfWidth),
                y: playerPos.y + spawnBoxHalfHeight + 50
            )
        case 1: // Right edge of spawn box
            spawnPosition = CGPoint(
                x: playerPos.x + spawnBoxHalfWidth + 50,
                y: playerPos.y + CGFloat.random(in: -spawnBoxHalfHeight...spawnBoxHalfHeight)
            )
        case 2: // Bottom edge of spawn box
            spawnPosition = CGPoint(
                x: playerPos.x + CGFloat.random(in: -spawnBoxHalfWidth...spawnBoxHalfWidth),
                y: playerPos.y - spawnBoxHalfHeight - 50
            )
        default: // Left edge of spawn box
            spawnPosition = CGPoint(
                x: playerPos.x - spawnBoxHalfWidth - 50,
                y: playerPos.y + CGFloat.random(in: -spawnBoxHalfHeight...spawnBoxHalfHeight)
            )
        }

        monster.setup(at: spawnPosition, targetPosition: playerEntity.sprite.position)
        // Add monster to world layer
        renderer?.world.worldLayer.addChild(monster.sprite)
        monsters.append(monster)

        print("Monster spawned at: \(spawnPosition), sprite added to scene, total monsters: \(monsters.count)")
    }

    /// Process wave spawning based on current level and elapsed time
    func processWaveSpawning(currentTime: TimeInterval) {
        guard let level = currentLevel else { return }

        // Initialize level start time on first update
        if levelStartTime == 0 {
            levelStartTime = currentTime
        }

        let elapsedTime = currentTime - levelStartTime

        // Check all waves to see if any should spawn
        for (index, wave) in level.spawnWaves.enumerated() {
            // Skip if this wave has already been spawned
            if spawnedWaves.contains(index) {
                continue
            }

            // Check if it's time to spawn this wave
            if elapsedTime >= wave.startTime {
                spawnWave(wave, waveIndex: index, currentTime: currentTime)
                spawnedWaves.insert(index)
            }
        }
    }

    /// Spawn a specific wave of monsters
    private func spawnWave(_ wave: SpawnWave, waveIndex: Int, currentTime: TimeInterval) {
        print("Spawning wave \(waveIndex + 1): \(wave.monsterCount) monsters")

        // Spawn monsters over time based on spawn interval
        for i in 0..<wave.monsterCount {
            let delay = TimeInterval(i) * wave.spawnInterval

            // Schedule spawn with delay
            let spawnAction = SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.run { [weak self] in
                    guard let self = self else { return }
                    // Pick random monster type from the wave
                    let monsterType = wave.monsterTypes.randomElement() ?? "Berserker"
                    self.spawnMonster(monsterType: monsterType)
                }
            ])

            run(spawnAction)
        }
    }

    func updateMonsters(_ deltaTime: TimeInterval) {
        // Guard player presence before updating monsters that target the player.
        guard let playerEntity = playerEntity else { return }

        for monster in monsters {
            if debugRotationEnabled {
                monster.rotationOffset = debugRotationOffset
            }
            monster.update(deltaTime: deltaTime, playerPosition: playerEntity.sprite.position, playerHitboxRadius: playerEntity.hitboxRadius)
        }
    }

    /// Check for monsters in contact range and update touching array
    func updateMonsterDamage(currentTime: TimeInterval) {
        guard let player = playerEntity else { return }

        let playerPos = player.sprite.position
        let damageRange = player.hitboxRadius + 20.0  // Slightly larger than hitbox

        // Track which monsters are currently touching
        var currentlyTouching = Set<ObjectIdentifier>()

        for monster in monsters {
            guard !monster.isDead else { continue }

            let monsterId = ObjectIdentifier(monster)

            // Calculate distance to player
            let dx = playerPos.x - monster.sprite.position.x
            let dy = playerPos.y - monster.sprite.position.y
            let distance = sqrt(dx*dx + dy*dy)

            // Check if monster is in damage range
            if distance <= damageRange {
                currentlyTouching.insert(monsterId)
            }
        }

        // Apply immediate damage for newly touching monsters (not in previous set)
        let newlyTouching = currentlyTouching.subtracting(touchingMonsters)
        if !newlyTouching.isEmpty {
            var immediateDamage: CGFloat = 0
            for monster in monsters {
                guard !monster.isDead else { continue }
                let monsterId = ObjectIdentifier(monster)
                if newlyTouching.contains(monsterId) {
                    immediateDamage += monster.damage
                }
            }

            if immediateDamage > 0 {
                player.takeDamage(Double(immediateDamage))
                print("Initial hit from \(newlyTouching.count) monsters! Damage: \(immediateDamage), Health: \(player.health)")

                // Check if player died
                if player.health <= 0 {
                    handlePlayerDeath()
                    touchingMonsters = currentlyTouching
                    return
                }
            }
        }

        // Update touching monsters set AFTER applying immediate damage
        touchingMonsters = currentlyTouching

        // Apply periodic damage to all touching monsters
        if !touchingMonsters.isEmpty && currentTime - lastDamageTime >= damageInterval {
            lastDamageTime = currentTime

            // Find all monsters in touching set and apply damage
            var totalDamage: CGFloat = 0
            for monster in monsters {
                guard !monster.isDead else { continue }
                let monsterId = ObjectIdentifier(monster)

                if touchingMonsters.contains(monsterId) {
                    totalDamage += monster.damage
                }
            }

            if totalDamage > 0 {
                player.takeDamage(Double(totalDamage))
                print("Periodic damage from \(touchingMonsters.count) monsters! Damage: \(totalDamage), Health: \(player.health)")

                // Check if player died
                if player.health <= 0 {
                    handlePlayerDeath()
                }
            }
        }
    }

}
