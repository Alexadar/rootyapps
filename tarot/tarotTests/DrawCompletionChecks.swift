import XCTest
import RealityKit
import TarotKit
import CardMotionKit
@testable import Tarot

/// The completion path, per method — the device bug this file exists for: the draw hint
/// was hardcoded to three-card counts, so a ten-card draw announced "The spread is
/// complete" at three landings while the reading (correctly) never came. The hint is now
/// a pure policy, tested over every method's full landing sequence, and the whole
/// draw → land → transition → reading path runs headless for every method.
final class DrawCompletionChecks: XCTestCase {

    // MARK: The hint policy — every method, every landing count, both directions

    func testHintNeverSaysCompleteEarlyAndAlwaysSaysCompleteAtTheEnd() {
        for method in Spread.all {
            let n = method.positions.count
            for landed in 0...n {
                let key = AppModel.drawHintKey(landed: landed, slotCount: n)
                if landed < n {
                    XCTAssertNotEqual(key, "The spread is complete",
                                      "\(method.id): claimed complete at \(landed)/\(n)")
                } else {
                    XCTAssertEqual(key, "The spread is complete",
                                   "\(method.id): not complete at \(landed)/\(n)")
                }
            }
            // The countdown wording appears exactly where it's true.
            if n >= 2 {
                XCTAssertEqual(AppModel.drawHintKey(landed: n - 1, slotCount: n), "One more card")
            }
            if n >= 3 {
                XCTAssertEqual(AppModel.drawHintKey(landed: n - 2, slotCount: n),
                               "Two positions remain")
            }
            XCTAssertEqual(AppModel.drawHintKey(landed: 0, slotCount: n),
                           "Drag a card from the deck to a position")
        }
        // The ten-card regression, verbatim: three landings is NOT complete.
        XCTAssertEqual(AppModel.drawHintKey(landed: 3, slotCount: 10),
                       "Drag the next card to a position")
    }

    /// The policy emits only the five known catalog keys — every one lives in
    /// strings_ui.json, and the generator's zero-gap check guards their translations, so
    /// a new hint string that skipped the catalog fails here instead of shipping English.
    func testEveryHintKeyIsAKnownCatalogKey() {
        let keys: Set<String> = ["Drag a card from the deck to a position",
                                 "Two positions remain", "One more card",
                                 "The spread is complete",
                                 "Drag the next card to a position"]
        for method in Spread.all {
            for landed in 0...method.positions.count {
                let key = AppModel.drawHintKey(landed: landed,
                                               slotCount: method.positions.count)
                XCTAssertTrue(keys.contains(key), "unexpected hint key: \(key)")
            }
        }
    }

    // MARK: The full path — scripted draw through AppModel.step, per method

    @MainActor
    func testEveryMethodDrawsToTheReadingScreen() {
        // Selection persists through UserDefaults — save and restore so a test run never
        // changes the owner's actual choice (the test host is the real app).
        let savedMethod = UserDefaults.standard.string(forKey: "selectedMethodID")
        let savedDeck = UserDefaults.standard.string(forKey: "selectedDeckID")
        defer {
            UserDefaults.standard.set(savedMethod, forKey: "selectedMethodID")
            UserDefaults.standard.set(savedDeck, forKey: "selectedDeckID")
        }

        for method in Spread.all {
            for deck in Deck.all where deck.id == "classic-1909" || method.id == "celtic-cross" {
                let model = AppModel(renderer: StubRenderer(),
                                     writer: UnavailableWriter())
                model.selectedMethodID = method.id
                model.selectedDeckID = deck.id
                model.prepareScene()
                model.startDraw()
                XCTAssertEqual(model.screen, .draw, method.id)

                let config = model.config
                let dt = 1.0 / 60.0
                // One drag per slot: press near the deck, glide to the slot, release —
                // the same choreography the Debug autopilot ships.
                for s in 0..<config.slotCount {
                    var t = 0.0
                    while t < 2.0 {
                        let drag = min(max((t - 0.1) / 1.0, 0), 1)
                        let eased = drag * drag * (3 - 2 * drag)
                        model.pointerX = config.deckX + (config.slotX[s] - config.deckX) * eased
                        model.pointerZ = config.deckZ + (config.slotZ[s] - config.deckZ) * eased
                        model.pointerDown = t >= 0.02 && t < 1.2
                        model.step(dt: dt)
                        t += dt
                    }
                }
                model.pointerDown = false
                // Let hitstop, the hero beat and the 1.1 s reading transition play out.
                for _ in 0..<Int(5.0 / dt) { model.step(dt: dt) }

                XCTAssertEqual(model.screen, .reading,
                               "\(method.id)/\(deck.id): never reached the reading")
                XCTAssertEqual(model.reading?.cards.count, method.positions.count)
                XCTAssertEqual(model.drawnLanes.count, method.positions.count)
                if let world = model.world {
                    let landed = (world.phase .== MotionWorld.Phase.landed).setLanes(world: 0)
                    XCTAssertEqual(landed.count, config.slotCount,
                                   "\(method.id): \(landed.count) landed")
                }
            }
        }
    }
}

// MARK: - Stubs

/// A renderer-shaped nothing: the completion path must not depend on RealityKit at all.
@MainActor
private final class StubRenderer: CardRenderer {
    let sceneRoot = Entity()
    func prepare() {}
    func setLayout(config: MotionConfig, spread: Spread) {}
    func setViewSize(_ size: CGSize) {}
    func build(deck: Deck, faces: [Int: CardArt], back: CardArt, reversedLanes: Set<Int>) {}
    func apply(frame: PoseFrame) {}
    func tick(dt: Double) {}
    func setARMode(_ on: Bool) {}
    func fixateARPlacement() {}
    func unfixARPlacement() {}
    func arDebugStatus() -> String { "" }
    func playRevealBurst(lane: Int, hero: Bool) {}
    func setHeroFocus(_ on: Bool) {}
    func setViewerFocus(lane: Int?) {}
    func lane(for entity: Entity) -> Int? { nil }
    func tablePoint(fromView point: CGPoint, viewSize: CGSize) -> (x: Double, z: Double) { (0, 0) }
}

/// Keeps the composer out of the run entirely — completion is a motion fact, not a
/// writing fact.
@MainActor
private final class UnavailableWriter: ReadingWriter {
    var availability: WriterAvailability { .deviceNotEligible }
    func write(reading: Reading, deck: Deck, spread: Spread) -> AsyncThrowingStream<PassageDraft, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
