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
        addChild(monster.sprite)
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
            monster.update(deltaTime: deltaTime, playerPosition: playerEntity.sprite.position)
        }
    }
}
