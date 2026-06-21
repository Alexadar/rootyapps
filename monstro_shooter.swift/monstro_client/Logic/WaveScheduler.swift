import Foundation

/// Pure wave-scheduling / victory math extracted from `GameScene.processWaveSpawning`.
enum WaveScheduler {
    /// Total monsters expected across all waves.
    static func expectedTotal(_ waves: [SpawnWave]) -> Int {
        waves.reduce(0) { $0 + $1.monsterCount }
    }

    /// Indices of waves that are due to spawn at `elapsedTime` and have not been spawned yet.
    static func wavesDue(at elapsedTime: TimeInterval,
                         alreadySpawned: Set<Int>,
                         waves: [SpawnWave]) -> [Int] {
        var due: [Int] = []
        for (index, wave) in waves.enumerated() {
            if alreadySpawned.contains(index) { continue }
            if elapsedTime >= wave.startTime { due.append(index) }
        }
        return due
    }

    /// Victory when the player has killed all expected monsters.
    static func isVictory(killCount: Int, waves: [SpawnWave]) -> Bool {
        killCount >= expectedTotal(waves)
    }
}
