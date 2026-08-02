import XCTest
import ProducerKit
@testable import producertycoon_swift

/// App-level smoke: the bundled coevolved world boots and one full weekly
/// loop drives through the real engine. The exhaustive math/parity suite
/// lives in ProducerKit (run `swift test` in Kits/Producer/ProducerKit).
final class AppSmokeTests: XCTestCase {
    @MainActor
    func testGameBootsAndPlaysAWeek() throws {
        let game = GameViewModel()
        XCTAssertEqual(game.engine.week, 0)
        XCTAssertEqual(game.engine.candidates.count, 2)
        game.sign(0)
        XCTAssertEqual(game.engine.rosterCount, 1)
        game.endWeek()
        XCTAssertEqual(game.engine.week, 1)
        XCTAssertFalse(game.engine.canEndWeek)   // locked until a release
        game.release(slot: 0)
        XCTAssertNotNil(game.lastRelease)
        XCTAssertTrue(game.engine.canEndWeek)
    }

    @MainActor
    func testNewGameResets() {
        let game = GameViewModel()
        game.sign(0)
        game.endWeek()
        game.newGame()
        XCTAssertEqual(game.engine.week, 0)
        XCTAssertEqual(game.engine.rosterCount, 0)
        XCTAssertEqual(game.engine.outcome, .running)
    }
}
