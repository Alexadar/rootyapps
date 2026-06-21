import Testing
import Foundation
@testable import monstro_client

@MainActor
struct WaveSchedulerTests {
    func waves() -> [SpawnWave] {
        [
            SpawnWave(startTime: 0, monsterCount: 3, monsterTypeIDs: [1]),
            SpawnWave(startTime: 5, monsterCount: 5, monsterTypeIDs: [2]),
            SpawnWave(startTime: 10, monsterCount: 2, monsterTypeIDs: [3]),
        ]
    }

    @Test func expectedTotalSumsMonsterCounts() {
        #expect(WaveScheduler.expectedTotal(waves()) == 10)
    }

    @Test func expectedTotalOfEmptyIsZero() {
        #expect(WaveScheduler.expectedTotal([]) == 0)
    }

    @Test func wavesDueRespectsStartTimeAndAlreadySpawned() {
        let due = WaveScheduler.wavesDue(at: 6, alreadySpawned: [0], waves: waves())
        #expect(due == [1])   // index 0 already spawned, index 2 not yet due
    }

    @Test func wavesDueReturnsAllReadyWaves() {
        let due = WaveScheduler.wavesDue(at: 100, alreadySpawned: [], waves: waves())
        #expect(due == [0, 1, 2])
    }

    @Test func wavesDueEmptyBeforeAnyStart() {
        let due = WaveScheduler.wavesDue(at: -1, alreadySpawned: [], waves: waves())
        #expect(due.isEmpty)
    }

    @Test func victoryWhenKillCountReachesTotal() {
        #expect(WaveScheduler.isVictory(killCount: 10, waves: waves()))
        #expect(WaveScheduler.isVictory(killCount: 11, waves: waves()))
        #expect(!WaveScheduler.isVictory(killCount: 9, waves: waves()))
    }
}

@MainActor
struct FrameOrderTests {
    @Test func extractsLastNumericRunAsFrameNumber() {
        #expect(FrameOrder.frameNumber(from: "Bird5/dying_01") == 1)
        #expect(FrameOrder.frameNumber(from: "Bug/walk_10") == 10)
        #expect(FrameOrder.frameNumber(from: "Berserker2/walk_07") == 7)
    }

    @Test func nonDigitNameIsZero() {
        #expect(FrameOrder.frameNumber(from: "no_digits_here") == 0)
    }

    @Test func sortsByFrameNumberNotMonsterId() {
        // The bug this regression-guards: sorting by the FIRST number (monster id) scrambled frames.
        let input = ["Bird5/dying_02", "Bird5/dying_10", "Bird5/dying_01"]
        let sorted = FrameOrder.sortedFrameNames(input)
        #expect(sorted == ["Bird5/dying_01", "Bird5/dying_02", "Bird5/dying_10"])
    }
}

@MainActor
struct DeviceFPSTests {
    @Test func validatedPassesThroughSupportedValues() {
        #expect(DeviceFPS.validated(120, options: [30, 60, 120]) == 120)
        #expect(DeviceFPS.validated(30, options: [30, 60, 120]) == 30)
    }

    @Test func validatedFallsBackOnUnsupportedValue() {
        #expect(DeviceFPS.validated(45, options: [30, 60, 120]) == 60)
        #expect(DeviceFPS.validated(0, options: [30, 60, 120], fallback: 30) == 30)
    }

    @Test func highTierDevicesGet120() {
        #expect(DeviceFPS.fps(forDeviceIdentifier: "iPhone15,2") == 120)
        #expect(DeviceFPS.fps(forDeviceIdentifier: "iPhone16,1") == 120)
        #expect(DeviceFPS.fps(forDeviceIdentifier: "iPad14,1") == 120)
    }

    @Test func lowTierDevicesGet60() {
        #expect(DeviceFPS.fps(forDeviceIdentifier: "iPhone12,1") == 60)
        #expect(DeviceFPS.fps(forDeviceIdentifier: "iPad8,1") == 60)
    }
}
