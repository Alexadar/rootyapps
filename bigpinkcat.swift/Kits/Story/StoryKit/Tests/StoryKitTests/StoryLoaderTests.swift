import XCTest
@testable import StoryKit

/// The loader has never worked, so these tests pin the schema that actually exists rather than the
/// one the 2025 model assumed. Sample below is a verbatim excerpt of `dialog_1_3.yaml`.
final class StoryLoaderTests: XCTestCase {

    private let sample = """
    - guidelines:
      - Analyze the crystal's data layers for precise coordinates
      - 'Options of phase_3_option_2:'
      - Give cat to eat it, maybe it will be beneficial
    - story_dialogs:
      - character_id: 2
        character_name: Big Pink Cat
        character_text: Interesting. Very interesting. I didn't expect you to choose that.
        id: 0
      - character_id: 1
        character_name: Astronaut
        character_text: 'Why? Is it dangerous?'
        id: 1
        options:
        - option_text: Let the cat eat the crystal
        - option_text: Submerge the crystal in the glowing pond
        - option_text: Ask the crystal how it feels
        - option_text: Charge it with magic tomatoes
    """

    func testParsesTheRealSchema() throws {
        let node = try StoryLoader.parse(id: "dialog_1_3", yaml: sample)
        XCTAssertEqual(node.id, "dialog_1_3")
        XCTAssertEqual(node.guidelines.count, 3, "the author's outline is retained")
        XCTAssertEqual(node.lines.count, 2)
        XCTAssertEqual(node.lines[0].characterName, "Big Pink Cat")
        XCTAssertEqual(node.options.count, 4)
        XCTAssertEqual(node.options[3], "Charge it with magic tomatoes")
    }

    func testApostrophesAndColonsSurviveParsing() {
        // The reason this Kit takes a YAML dependency rather than a hand-rolled subset parser:
        // the dialogue is full of both, and a naive split on ":" corrupts it silently.
        let node = try? StoryLoader.parse(id: "x", yaml: sample)
        XCTAssertEqual(node?.lines[0].text,
                       "Interesting. Very interesting. I didn't expect you to choose that.")
        XCTAssertEqual(node?.lines[1].text, "Why? Is it dangerous?")
    }

    func testFinalWordsIsAMapNotAScalar() throws {
        // The third of the three 2025 mismatches: the model expected a scalar
        // `final_words_of_the_story`, the content has a map keyed option_1…option_4.
        let yaml = """
        - story_dialogs:
          - character_id: 1
            character_name: Astronaut
            character_text: Choose.
            id: 0
            final_words:
              option_1: "The astronaut returned to Earth carrying equations."
              option_2: "The astronaut woke in the medical bay."
        """
        let node = try StoryLoader.parse(id: "dialog_1_1_1", yaml: yaml)
        XCTAssertEqual(node.finalWords.count, 2)
        XCTAssertTrue(node.isTerminal, "a node with final_words is an ending")
        XCTAssertEqual(node.finalWords["option_1"],
                       "The astronaut returned to Earth carrying equations.")
    }

    func testStubIsDetectedNotSilentlyAccepted() throws {
        // dialog_1_1_2.yaml in full — the author's seed, never expanded.
        let node = try StoryLoader.parse(
            id: "dialog_1_1_2",
            yaml: "- guidelines:\n    - astronaut chooses \"Red\", \"Okay whatever it is\"\n")
        XCTAssertTrue(node.isStub, "guidelines with no dialogue is a stub, and must be visible")
        XCTAssertTrue(node.lines.isEmpty)
    }

    func testChildIDFollowsTheNamingConvention() {
        let node = StoryNode(id: "dialog_1_1", guidelines: [], lines: [],
                             options: ["a", "b", "c", "d"], finalWords: [:])
        XCTAssertEqual(node.childID(forOption: 3), "dialog_1_1_3",
                       "the tree structure lives in the file name — what the 2025 loader missed")
    }

    func testValidatorNamesEveryGapRatherThanDeadEnding() {
        // The honest accounting. A loader that silently dead-ends is how fifteen of sixteen paths
        // shipped going nowhere.
        let root = StoryNode(id: "dialog_1", guidelines: [], lines: [],
                             options: ["w", "x", "y", "z"], finalWords: [:])
        let child = StoryNode(id: "dialog_1_1", guidelines: ["seed"], lines: [],
                              options: [], finalWords: [:])
        let graph = StoryGraph(nodes: ["dialog_1": root, "dialog_1_1": child])
        let gaps = graph.validate()
        XCTAssertEqual(gaps.count, 4, "one stub plus three absent children")
        XCTAssertEqual(gaps.first { $0.missingID == "dialog_1_1" }?.kind, .stub)
        XCTAssertEqual(gaps.first { $0.missingID == "dialog_1_2" }?.kind, .absent)
    }

    func testMalformedYamlThrowsInsteadOfReturningEmpty() {
        // The 2025 loader printed a warning and returned an empty model, turning a missing folder
        // into a blank screen at runtime. Errors must be loud.
        XCTAssertThrowsError(try StoryLoader.parse(id: "bad", yaml: "just a string"))
        XCTAssertThrowsError(try StoryLoader.load(directory: URL(fileURLWithPath: "/nope/nowhere")))
    }
}
