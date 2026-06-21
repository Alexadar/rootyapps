import SpriteKit

// MARK: - Monster Management
extension GameScene {

    /// Spawn a monster at the edge of the viewport (just off-screen)
    func spawnMonster(monsterTypeID: Int) {
        // Guard player — monsters need a target; skip spawning if player missing.
        guard let playerEntity = playerEntity else { return }

        // Create monster from config - fail fast if not found
        guard let config = MonsterRegistry.shared.getConfig(forID: monsterTypeID) else {
            fatalError("[GameScene] No config for monster ID \(monsterTypeID)")
        }

        let monster = Monster(config: config)
        monster.monsterTypeID = monsterTypeID

        // Spawn just outside visible viewport (adjusted for camera scale)
        // This makes monsters appear faster than spawning from far away
        let playerPos = playerEntity.sprite.position
        let viewportSize = self.size
        let cameraScale = GameConstants.cameraScale
        let spawnBuffer: CGFloat = 100  // Spawn 100 points outside visible area

        // Calculate spawn box based on what's visible on screen
        let spawnBoxHalfWidth = (viewportSize.width / 2) / cameraScale + spawnBuffer
        let spawnBoxHalfHeight = (viewportSize.height / 2) / cameraScale + spawnBuffer

        let spawnSide = Int.random(in: 0...3)
        var spawnPosition: CGPoint

        switch spawnSide {
        case 0: // Top edge
            spawnPosition = CGPoint(
                x: playerPos.x + CGFloat.random(in: -spawnBoxHalfWidth...spawnBoxHalfWidth),
                y: playerPos.y + spawnBoxHalfHeight
            )
        case 1: // Right edge
            spawnPosition = CGPoint(
                x: playerPos.x + spawnBoxHalfWidth,
                y: playerPos.y + CGFloat.random(in: -spawnBoxHalfHeight...spawnBoxHalfHeight)
            )
        case 2: // Bottom edge
            spawnPosition = CGPoint(
                x: playerPos.x + CGFloat.random(in: -spawnBoxHalfWidth...spawnBoxHalfWidth),
                y: playerPos.y - spawnBoxHalfHeight
            )
        default: // Left edge
            spawnPosition = CGPoint(
                x: playerPos.x - spawnBoxHalfWidth,
                y: playerPos.y + CGFloat.random(in: -spawnBoxHalfHeight...spawnBoxHalfHeight)
            )
        }

        monster.setup(at: spawnPosition, targetPosition: playerEntity.sprite.position)
        // Add monster to world layer
        renderer?.world.worldLayer.addChild(monster.sprite)
        monsters.append(monster)
    }

    /// Process wave spawning based on current level and elapsed time
    func processWaveSpawning(currentTime: TimeInterval) {
        guard let level = currentLevel else { return }

        // Initialize level start time on first update
        if levelStartTime == 0 {
            levelStartTime = currentTime
        }

        let elapsedTime = currentTime - levelStartTime

        // Wave-due decision lives in WaveScheduler (pure, unit-tested).
        for index in WaveScheduler.wavesDue(at: elapsedTime, alreadySpawned: spawnedWaves, waves: level.spawnWaves) {
            spawnWave(level.spawnWaves[index], waveIndex: index, currentTime: currentTime)
            spawnedWaves.insert(index)
        }

        // Check for victory: all expected monsters killed
        checkVictoryCondition(level: level)
    }

    /// Check if player has won (killed all expected monsters)
    private func checkVictoryCondition(level: GameLevel) {
        // Victory math lives in WaveScheduler (pure, unit-tested).
        guard WaveScheduler.isVictory(killCount: killCount, waves: level.spawnWaves) else { return }

        // Trigger victory
        handleVictory()
    }

    /// Spawn a specific wave of monsters
    private func spawnWave(_ wave: SpawnWave, waveIndex: Int, currentTime: TimeInterval) {

        // Spawn monsters over time based on spawn interval
        for i in 0..<wave.monsterCount {
            let delay = TimeInterval(i) * wave.spawnInterval

            // Schedule spawn with delay
            let spawnAction = SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.run { [weak self] in
                    guard let self = self else { return }
                    // Pick random monster type ID from the wave - fail fast if empty
                    guard let monsterTypeID = wave.monsterTypeIDs.randomElement() else {
                        fatalError("[GameScene] Wave has no monster type IDs")
                    }
                    self.spawnMonster(monsterTypeID: monsterTypeID)
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
        let playerRadius = player.hitboxRadius

        // Track which monsters are currently touching
        var currentlyTouching = Set<ObjectIdentifier>()

        for monster in monsters {
            guard !monster.isDead else { continue }

            let monsterId = ObjectIdentifier(monster)

            // Calculate distance to player
            let dx = playerPos.x - monster.sprite.position.x
            let dy = playerPos.y - monster.sprite.position.y
            let distanceSquared = dx*dx + dy*dy

            // Damage range accounts for both player and monster sizes + small buffer
            let monsterRadius = monster.boxSize.width / 2.0
            let damageRange = playerRadius + monsterRadius + 5.0
            let damageRangeSquared = damageRange * damageRange

            // Check if monster is in damage range (use squared to avoid sqrt)
            if distanceSquared <= damageRangeSquared {
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

                // Check if player died
                if player.health <= 0 {
                    handlePlayerDeath()
                }
            }
        }
    }

}
