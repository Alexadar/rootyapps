import XCTest
@testable import MonstroSim

// Infra tests for the GPU-only package: seedable RNG + loading the real game data/maps.
// (CPU-sim parity tests were removed with the CPU engine.)
final class InfraTests: XCTestCase {

    var clientRoot: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("monstro_client").path
    }

    func testSeededRNGIsDeterministic() {
        var a = SeededGenerator(seed: 123), b = SeededGenerator(seed: 123)
        for _ in 0..<100 { XCTAssertEqual(a.next(), b.next()) }
        var c = SeededGenerator(seed: 124), d = SeededGenerator(seed: 123)
        XCTAssertNotEqual(d.next(), c.next())
    }

    func testLoadsRealConfigs() throws {
        let data = GameData.load(clientRoot: clientRoot)
        try XCTSkipIf(data.monsters.isEmpty, "monstro_client configs not found at \(clientRoot)")
        let bug = try XCTUnwrap(data.monsters[1])
        XCTAssertEqual(bug.speed, 150, accuracy: 1e-6)
        XCTAssertNotNil(data.weapons[1])
        XCTAssertNotNil(data.exoskeletons[1])
    }

    func testLoadsRealMapIntoLevel() throws {
        let data = GameData.load(clientRoot: clientRoot)
        try XCTSkipIf(data.monsters.isEmpty, "configs not found")
        let map = try XCTUnwrap(ConfigLoader.loadMap(path: clientRoot + "/Resources/MapConfigs/map_0014.json"))
        let level = SimLevel(map)
        XCTAssertGreaterThan(level.expectedTotal, 0)
        XCTAssertFalse(level.waves.isEmpty)
    }
}
