import XCTest
import RealityKit
import TarotKit
import CardMotionKit
@testable import Tarot

/// Filming scenarios. Almost everything about a take is decided by arithmetic and parsing,
/// so almost everything about it can be proven here, on a Mac, with no device and no camera.
/// What is left over — whether it looks good — is what the take itself is for.
final class FilmScenarioChecks: XCTestCase {

    // MARK: The YAML reader

    private let sample = """
    # a comment at the top
    id: demo
    skin: midnight
    deck: classic-1909
    method: three-card
    seed: 7
    date: 2026-08-17T21:00:00Z
    question: "Will I be rich?"
    cards:
      - Ten of Pentacles
      - Wheel of Fortune
      - Nine of Cups
    passages:
      - |
        First passage.
        Still the first passage.
      - |
        Second passage.
      - |
        Third passage.
    synthesis: |
      The synthesis.
    timing:
      typeInterval: 0.11
      pauseAfter: 1.4
      settle: 0.9
      perCard: 2.8
      hold: 14.0
    writing:
      firstDelay: 9.0
      charsPerSecond: 55
      chunkInterval: 0.08
    """

    func testReadsTheSchemaItWasBuiltFor() throws {
        let scenario = try FilmScenario(yaml: sample)
        XCTAssertEqual(scenario.id, "demo")
        XCTAssertEqual(scenario.seed, 7)
        XCTAssertEqual(scenario.question, "Will I be rich?")     // quotes stripped
        XCTAssertEqual(scenario.cards, [.minor(.pentacles, .ten), .major(10), .minor(.cups, .nine)])
        XCTAssertEqual(scenario.passages.count, 3)
        // A block scalar keeps its interior newlines and exactly one trailing newline.
        XCTAssertEqual(scenario.passages[0], "First passage.\nStill the first passage.\n")
        XCTAssertEqual(scenario.synthesis, "The synthesis.\n")
        XCTAssertEqual(scenario.timing.perCard, 2.8)
        XCTAssertEqual(scenario.writing.charsPerSecond, 55)
        XCTAssertTrue(scenario.interpretations, "a take must not inherit a saved 'off'")
    }

    func testCardsResolveByNameAndById() {
        XCTAssertEqual(FilmScenario.card(named: "Ten of Pentacles"), .minor(.pentacles, .ten))
        XCTAssertEqual(FilmScenario.card(named: "  the sun "), .major(19))
        XCTAssertEqual(FilmScenario.card(named: "major-19"), .major(19))
        XCTAssertEqual(FilmScenario.card(named: "cups-ace"), .minor(.cups, .ace))
        XCTAssertNil(FilmScenario.card(named: "Ten of Goblets"))
    }

    /// A copied-in real YAML must FAIL, not half-parse: a take filmed from a partly-read
    /// scenario is the expensive failure, because it only shows up in the footage.
    func testRefusesEverythingItDoesNotImplement() {
        let cases: [(String, String)] = [
            ("tabs", "id: demo\n\tskin: midnight\n"),
            ("flow list", "id: demo\ncards: [a, b]\n"),
            ("flow map", "id: demo\ntiming: {a: 1}\n"),
            ("anchor", "id: demo\nbase: &anchor x\n"),
            ("tag", "id: demo\n!!str x\n"),
            ("folded", "id: demo\ntext: >\n  folded\n"),
            ("multi-document", "---\nid: demo\n"),
            ("duplicate key", "id: demo\nid: other\n"),
            ("odd indent", "timing:\n   typeInterval: 1\n"),
            ("unterminated quote", "id: \"demo\n"),
            ("no colon", "id demo\n"),
        ]
        for (name, yaml) in cases {
            XCTAssertThrowsError(try YAMLReader.parse(yaml), name) { error in
                guard let scenarioError = error as? ScenarioError else {
                    return XCTFail("\(name): wrong error type")
                }
                XCTAssertGreaterThan(scenarioError.line, 0, "\(name): no line number")
            }
        }
    }

    func testCommentsAreLineStartOnlyAndNeverInsideABlock() throws {
        let yaml = """
        # leading
        question: "a # b"
        note: |
          # not a comment, this is text
          real line
        """
        let root = try YAMLReader.parse(yaml)
        guard case .scalar(let question)? = root["question"],
              case .scalar(let note)? = root["note"] else { return XCTFail("parse shape") }
        XCTAssertEqual(question, "a # b")
        XCTAssertEqual(note, "# not a comment, this is text\nreal line\n")
    }

    // MARK: Validation — the mistakes that would waste a shoot

    func testValidationRefusesAMisauthoredTake() {
        func rejects(_ mutate: (inout String) -> Void, _ why: String) {
            var yaml = sample
            mutate(&yaml)
            XCTAssertThrowsError(try FilmScenario(yaml: yaml), why)
        }
        rejects({ $0 = $0.replacingOccurrences(of: "  - Nine of Cups\n", with: "") },
                "card count must match the method's arity")
        rejects({ $0 = $0.replacingOccurrences(of: "Nine of Cups", with: "Ten of Pentacles") },
                "the same card twice")
        rejects({ $0 = $0.replacingOccurrences(of: "Nine of Cups", with: "Nine of Goblets") },
                "unknown card")
        rejects({ $0 = $0.replacingOccurrences(of: "method: three-card", with: "method: no-such") },
                "unknown method")
        rejects({ $0 = $0.replacingOccurrences(of: "deck: classic-1909", with: "deck: tarot-de-marseille") },
                "unknown deck")
        rejects({ $0 = $0.replacingOccurrences(of: "perCard: 2.8", with: "perCard: 1.2") },
                "perCard under what a card needs to land")
        rejects({ $0 = $0.replacingOccurrences(of: "seed: 7", with: "seed: later") },
                "seed must be a number")
    }

    /// A single-card method has no synthesis field in its generable form, so a scenario with
    /// one would be filming a screen the app cannot produce.
    func testDailyCardMayNotCarryASynthesis() {
        let yaml = sample
            .replacingOccurrences(of: "method: three-card", with: "method: daily-card")
            .replacingOccurrences(of: "  - Wheel of Fortune\n  - Nine of Cups\n", with: "")
        XCTAssertThrowsError(try FilmScenario(yaml: yaml))
    }

    // MARK: The timeline

    func testTheTimelineNeverPressesWhenAPressWouldBreakTheBeat() throws {
        let scenario = try FilmScenario(yaml: sample)
        let timeline = ScenarioTimeline(scenario: scenario, config: .threeCard)
        // A pressed pointer zeroes the landing hitstop and collapses the 1.1 s transition
        // into the reading — so after the last release the director must never press again.
        var t = timeline.lastReleaseAt
        while t < timeline.endsAt {
            XCTAssertFalse(timeline.beat(at: t).press,
                           "pressed at \(t), after the last release")
            t += 1.0 / 60
        }
        // And within each card, the release must happen before the flight completes.
        for k in 0..<3 {
            let release = timeline.cardStartsAt(k) + scenario.timing.grabHold + scenario.timing.dragDuration
            XCTAssertTrue(timeline.beat(at: release - 0.01).press)
            XCTAssertFalse(timeline.beat(at: release + 0.01).press)
            XCTAssertGreaterThanOrEqual(timeline.cardStartsAt(k + 1) - release, 0.55 + 0.9,
                                        "card \(k) has no room to fly, land and play its hero beat")
        }
    }

    func testTheTimelineTypesThenDrawsThenHolds() throws {
        let scenario = try FilmScenario(yaml: sample)
        let timeline = ScenarioTimeline(scenario: scenario, config: .threeCard)
        XCTAssertEqual(timeline.beat(at: 0).typedCharacters, 0)
        XCTAssertFalse(timeline.beat(at: 0).shouldStartDraw)
        XCTAssertEqual(timeline.beat(at: timeline.typingEndsAt).typedCharacters,
                       scenario.question.count)
        XCTAssertFalse(timeline.beat(at: timeline.drawStartsAt - 0.01).shouldStartDraw)
        XCTAssertTrue(timeline.beat(at: timeline.drawStartsAt + 0.01).shouldStartDraw)
        XCTAssertFalse(timeline.beat(at: timeline.endsAt - 0.1).isOver)
        XCTAssertTrue(timeline.beat(at: timeline.endsAt).isOver)
        // Every drag starts on the deck and ends on its slot — checked against the real config.
        let config = MotionConfig.threeCard
        for k in 0..<3 {
            let grab = timeline.beat(at: timeline.cardStartsAt(k) + 0.01)
            XCTAssertEqual(hypot(grab.pointerX - config.deckX, grab.pointerZ - config.deckZ), 0,
                           accuracy: config.deckGrabRadius)
            let release = timeline.beat(at: timeline.cardStartsAt(k) + scenario.timing.grabHold
                                        + scenario.timing.dragDuration - 0.01)
            XCTAssertEqual(hypot(release.pointerX - config.slotX[k], release.pointerZ - config.slotZ[k]), 0,
                           accuracy: config.snapRadius)
        }
    }

    /// The writing has to still be arriving when the panel opens. Too early and the reading
    /// is finished before the reader sees it — the single easiest way to film a dud.
    func testTextIsStillArrivingWhenThePanelOpens() throws {
        let scenario = try FilmScenario(yaml: sample)
        let timeline = ScenarioTimeline(scenario: scenario, config: .threeCard)
        let writingStarts = timeline.drawStartsAt + scenario.writing.firstDelay
        XCTAssertLessThan(writingStarts, timeline.readingOpensAt,
                          "the first words must land before the panel opens")
        let characters = scenario.passages.reduce(0) { $0 + $1.count } + (scenario.synthesis?.count ?? 0)
        let writingEnds = writingStarts + Double(characters) / scenario.writing.charsPerSecond
        XCTAssertGreaterThan(writingEnds, timeline.readingOpensAt,
                            "the reading is over before the panel opens — nothing to watch")
        XCTAssertLessThan(writingEnds, timeline.endsAt, "the take ends mid-sentence")
    }

    // MARK: The scripted writer

    func testDraftsAreCumulativeAndShapedLikeRealGeneration() {
        let passages = ["First passage here.", "Second passage here.", "Third one here."]
        let synthesis = "And the synthesis."
        let total = passages.reduce(0) { $0 + $1.count } + synthesis.count
        var previous = PassageDraft()
        for budget in stride(from: 0, through: total + 20, by: 3) {
            let draft = ScriptedWriter.draft(budget: budget, passages: passages, synthesis: synthesis)
            // Never an empty element: the panel draws a gold position label per element.
            XCTAssertFalse(draft.passages.contains(where: \.isEmpty))
            // Sequential fill, and monotone growth.
            XCTAssertGreaterThanOrEqual(draft.passages.count, previous.passages.count)
            for (index, text) in previous.passages.enumerated() where draft.passages.indices.contains(index) {
                XCTAssertTrue(draft.passages[index].hasPrefix(text) || draft.passages[index] == text,
                              "passage \(index) shrank or changed under it")
            }
            // Synthesis only once every passage is complete.
            if draft.synthesis != nil {
                XCTAssertEqual(draft.passages, passages, "synthesis arrived before the passages")
            }
            previous = draft
        }
        let final = ScriptedWriter.draft(budget: total, passages: passages, synthesis: synthesis)
        XCTAssertEqual(final.passages, passages)
        XCTAssertEqual(final.synthesis, synthesis)
    }

    func testPartialPassagesStopOnWordBoundaries() {
        let draft = ScriptedWriter.draft(budget: 8, passages: ["hello there world"], synthesis: nil)
        XCTAssertEqual(draft.passages.first, "hello", "a half-word makes the reveal frontier stutter")
    }

    // MARK: Forcing the cards

    func testForcingRewritesIdentitiesAndKeepsEverythingElse() {
        let original = Shuffler.draw(deck: .classic1909, spread: .threeCard, seed: 42,
                                     allowsReversals: false, date: Date(timeIntervalSince1970: 0),
                                     question: "Will I be rich?")
        let wanted: [Card] = [.minor(.pentacles, .ten), .major(10), .minor(.cups, .nine)]
        let forced = AppModel.forcing(wanted, in: original)
        XCTAssertEqual(forced.cards.map(\.card), wanted)
        XCTAssertEqual(forced.cards.map(\.positionIndex), [0, 1, 2])
        XCTAssertEqual(forced.id, original.id)              // the panel keys onChange off this
        XCTAssertEqual(forced.seed, original.seed)
        XCTAssertEqual(forced.date, original.date)
        XCTAssertEqual(forced.question, original.question)
        XCTAssertEqual(forced.deckID, original.deckID)
        XCTAssertEqual(forced.spreadID, original.spreadID)
        // A mis-authored scenario films the real draw rather than a half-forced one.
        XCTAssertEqual(AppModel.forcing(nil, in: original).cards, original.cards)
        XCTAssertEqual(AppModel.forcing([.major(1)], in: original).cards, original.cards)
    }

    /// The invariant the whole design rests on: `drawnLanes[k] == permutation[k]`, and the
    /// face for position k is built onto THAT lane — so forcing identities in the reading
    /// cannot desynchronise the cards from the physical stack.
    @MainActor
    func testForcedCardsKeepTheLaneToFaceInvariant() throws {
        let scenario = try FilmScenario(yaml: sample)
        let saved = (UserDefaults.standard.string(forKey: "selectedMethodID"),
                     UserDefaults.standard.string(forKey: "selectedDeckID"))
        defer {
            UserDefaults.standard.set(saved.0, forKey: "selectedMethodID")
            UserDefaults.standard.set(saved.1, forKey: "selectedDeckID")
        }
        let model = AppModel(renderer: StubRenderer(), writer: ScriptedWriter(scenario: scenario))
        model.scenario = scenario
        model.selectedMethodID = scenario.methodID
        model.selectedDeckID = scenario.deckID
        model.prepareScene()
        model.startDraw()

        let order = Shuffler.permutation(count: 78, seed: scenario.seed)
        XCTAssertEqual(model.drawnLanes, Array(order.prefix(3)),
                       "lane order must still come from the seeded permutation")
        XCTAssertEqual(model.reading?.cards.map(\.card), scenario.cards)
    }

    // MARK: End to end, headless

    /// The whole take, through the real director: inject the scenario, then do nothing but
    /// step the model at 60 Hz. The question types itself, the draw fires, three cards land,
    /// the reading opens — with no launch arguments, no simulator and no camera.
    @MainActor
    func testTheWholeTakePlaysWithoutADevice() throws {
        let scenario = try FilmScenario(yaml: sample)
        let saved = (UserDefaults.standard.string(forKey: "selectedMethodID"),
                     UserDefaults.standard.string(forKey: "selectedDeckID"))
        defer {
            UserDefaults.standard.set(saved.0, forKey: "selectedMethodID")
            UserDefaults.standard.set(saved.1, forKey: "selectedDeckID")
        }
        let timeline = ScenarioTimeline(scenario: scenario, config: .threeCard)
        let model = AppModel(renderer: StubRenderer(), writer: ScriptedWriter(scenario: scenario))
        model.scenario = scenario
        model.selectedMethodID = scenario.methodID
        model.selectedDeckID = scenario.deckID
        model.prepareScene()

        var questionWasCompleteAtDraw: Bool?
        let dt = 1.0 / 60
        var t = 0.0
        while t < timeline.readingOpensAt + 0.5 {
            let wasMenu = model.screen == .menu
            model.step(dt: dt)
            if wasMenu, model.screen == .draw {
                questionWasCompleteAtDraw = model.question == scenario.question
            }
            t += dt
        }

        XCTAssertEqual(questionWasCompleteAtDraw, true,
                       "the question must be fully typed before the draw begins")
        XCTAssertEqual(model.screen, .reading, "the take never reached the reading")
        XCTAssertEqual(model.reading?.cards.map(\.card), scenario.cards)
        XCTAssertEqual(model.reading?.question, scenario.question)
        XCTAssertEqual(model.reading?.seed, scenario.seed, "the seed must be pinned")
        if let world = model.world {
            let landed = (world.phase .== MotionWorld.Phase.landed).setLanes(world: 0)
            XCTAssertEqual(landed.count, 3, "\(landed.count) cards landed")
        }
    }

    // MARK: Discipline

    /// Debug input comes through exactly one door, so a capture hook cannot quietly live
    /// somewhere a Release build still compiles it.
    func testProcessInfoIsReadInOnlyOneFile() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tarot")
        var offenders: [String] = []
        var scanned = 0
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            scanned += 1
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.contains("ProcessInfo.processInfo"),
               url.lastPathComponent != "LaunchOverride.swift" {
                offenders.append(url.lastPathComponent)
            }
        }
        XCTAssertGreaterThan(scanned, 20, "the scan found no sources — it would pass vacuously")
        XCTAssertEqual(offenders, [], "debug input must go through LaunchOverride")
        // …and the door itself must actually contain the thing, or the scan proves nothing.
        let door = try String(contentsOf: root.appendingPathComponent("App/LaunchOverride.swift"),
                              encoding: .utf8)
        XCTAssertTrue(door.contains("ProcessInfo.processInfo"))
    }

    /// A Release build must never carry pre-captured "AI" prose it did not generate.
    func testReleaseExcludesScenarioFiles() throws {
        let project = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("project.yml")
        let text = try String(contentsOf: project, encoding: .utf8)
        XCTAssertTrue(text.contains("EXCLUDED_SOURCE_FILE_NAMES: \"*.scenario.yaml\""),
                      "project.yml must exclude scenarios from Release")
    }
}

// MARK: - Stubs

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
