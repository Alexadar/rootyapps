import XCTest
@testable import MonstroSim

final class SimTests: XCTestCase {

    // Resolve the sibling monstro_client checkout from this file's path (robust to CWD).
    var clientRoot: String {
        URL(fileURLWithPath: #filePath)        // .../MonstroSim/Tests/MonstroSimTests/SimTests.swift
            .deletingLastPathComponent()        // MonstroSimTests
            .deletingLastPathComponent()        // Tests
            .deletingLastPathComponent()        // MonstroSim
            .deletingLastPathComponent()        // monstro_shooter.swift
            .appendingPathComponent("monstro_client").path
    }
    var mapPath: String { clientRoot + "/Resources/MapConfigs/map_0014.json" }

    // MARK: Formula parity with the app's Logic helpers
    func testCombatParity() {
        XCTAssertEqual(SimFormulas.actualDamage(incoming: 10, defense: 3, hitCount: 1), 7, accuracy: 1e-9)
        XCTAssertEqual(SimFormulas.actualDamage(incoming: 5, defense: 9, hitCount: 1), 0, accuracy: 1e-9)
        XCTAssertEqual(SimFormulas.actualDamage(incoming: 5, defense: 9, hitCount: 4), 0.4, accuracy: 1e-9)
    }

    func testSteeringMagnitudeEqualsSpeed() {
        let r = SimFormulas.steer(from: .zero, toward: Vec2(30, 40), velocity: .zero,
                                  speed: 100, turnRate: 34, useDirectSteering: true, stopDistance: 1, dt: 1)
        let v = try! XCTUnwrap(r).vel
        XCTAssertEqual(v.length, 100, accuracy: 1e-4)
    }

    func testSteeringStopsWithinStopDistance() {
        XCTAssertNil(SimFormulas.steer(from: .zero, toward: Vec2(5, 0), velocity: .zero,
                                       speed: 100, turnRate: 34, useDirectSteering: true, stopDistance: 10, dt: 1))
    }

    // MARK: RNG determinism (required for fair map eval)
    func testSeededRNGIsDeterministic() {
        var a = SeededGenerator(seed: 123), b = SeededGenerator(seed: 123)
        for _ in 0..<100 { XCTAssertEqual(a.next(), b.next()) }
        var c = SeededGenerator(seed: 124)
        var d = SeededGenerator(seed: 123)
        XCTAssertNotEqual(d.next(), c.next())
    }

    // MARK: Config loading from the real game files
    func testLoadsRealConfigs() throws {
        let data = GameData.load(clientRoot: clientRoot)
        try XCTSkipIf(data.monsters.isEmpty, "monstro_client configs not found at \(clientRoot)")
        let bug = try XCTUnwrap(data.monsters[1])
        XCTAssertEqual(bug.speed, 150, accuracy: 1e-6)   // Bug.yaml
        XCTAssertTrue(bug.useDirectSteering)
        XCTAssertNotNil(data.weapons[1])                  // pistol
        XCTAssertNotNil(data.exoskeletons[1])             // standard suit
    }

    // MARK: End-to-end episode runs and produces metrics
    func testEpisodeRunsAndTerminates() throws {
        let data = GameData.load(clientRoot: clientRoot)
        try XCTSkipIf(data.monsters.isEmpty, "monstro_client configs not found")
        let map = try XCTUnwrap(ConfigLoader.loadMap(path: mapPath))
        let level = SimLevel(map)
        XCTAssertGreaterThan(level.expectedTotal, 0)
        let r = Runner.runEpisode(data: data, level: level, weaponID: 1, exoID: 1,
                                  seed: 1, config: EpisodeConfig(maxSeconds: 60), policy: KiterPolicy())
        XCTAssertGreaterThan(r.survivalTime, 0)
        XCTAssertGreaterThanOrEqual(r.kills, 0)
        // Episode ends by death, victory, or truncation at the map's landingDuration (45s here).
        XCTAssertTrue(r.died || r.victory || r.survivalTime >= level.durationSeconds - 1)
    }

    // MARK: Determinism — same seed reproduces the same episode
    func testEpisodeIsReproducible() throws {
        let data = GameData.load(clientRoot: clientRoot)
        try XCTSkipIf(data.monsters.isEmpty, "monstro_client configs not found")
        let level = SimLevel(try XCTUnwrap(ConfigLoader.loadMap(path: mapPath)))
        func run() -> EpisodeResult {
            Runner.runEpisode(data: data, level: level, weaponID: 1, exoID: 1,
                              seed: 99, config: EpisodeConfig(maxSeconds: 30), policy: KiterPolicy())
        }
        let a = run(), b = run()
        XCTAssertEqual(a.survivalTime, b.survivalTime, accuracy: 1e-9)
        XCTAssertEqual(a.kills, b.kills)
        XCTAssertEqual(a.damageTaken, b.damageTaken, accuracy: 1e-9)
    }

    // MARK: Observation vector is the advertised fixed size
    func testObservationSize() {
        let data = GameData.load(clientRoot: clientRoot)
        guard !data.monsters.isEmpty, let map = ConfigLoader.loadMap(path: mapPath) else { return }
        let w = World(data: data, level: SimLevel(map), weaponID: 1, exoID: 1, seed: 1)
        XCTAssertEqual(w.observe().count, World.observationSize())
    }
}
