import Testing
import Foundation
@testable import PromptKit

/// ORACLES:
///  • INVARIANT — what the file says is what gets loaded. A hand-written reader's dangerous failure
///    is not a crash, it is quietly returning *fewer* prompts than the file contains: a quarter of
///    the corpus disappears and nothing reports it, so the counts are asserted against the resource.
///  • BEHAVIOUR — anything the reader does not understand throws, with a line number. This is a
///    restricted subset by design; the alternative to refusing is guessing.
@Suite("The prompt corpus file")
struct PromptCorpusTests {

    @Test("the shipped corpus loads, and everything in the file arrives")
    func shippedCorpusLoads() throws {
        let corpus = try PromptCorpus.load()
        #expect(corpus.curated.count == 20)
        #expect(corpus.palettes.count == 9)

        // Counted from the file itself rather than hard-coded, so this stays true when prompts are
        // added — what it is really asserting is that the reader is not dropping any.
        let url = try #require(Bundle.module.url(forResource: "sd15cn_sampleprompts",
                                                 withExtension: "yaml"))
        let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        let listItems = text.components(separatedBy: .newlines)
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- \"") }.count
        let loaded = corpus.curated.count
            + corpus.palettes.reduce(0) { $0 + $1.subjects.count + $1.lights.count + $1.treatments.count }
        #expect(loaded == listItems, "the reader dropped \(listItems - loaded) lines")
    }

    @Test("every palette is complete, because a missing axis composes nothing")
    func palettesAreComplete() throws {
        for palette in try PromptCorpus.load().palettes {
            #expect(!palette.name.isEmpty)
            #expect(!palette.subjects.isEmpty, "\(palette.name) has no subjects")
            #expect(!palette.lights.isEmpty, "\(palette.name) has no lights")
            #expect(!palette.treatments.isEmpty, "\(palette.name) has no treatments")
            #expect(Set(palette.subjects).count == palette.subjects.count,
                    "\(palette.name) repeats a subject")
        }
    }

    @Test("quotes and comments are handled, and indentation carries the structure")
    func readsTheSubsetItClaimsTo() throws {
        let corpus = try PromptCorpus.parse("""
        # a comment
        curated:
          - "one, with a comma"
          - two without quotes

        palettes:
          - name: Test
            subjects:
              - "a subject"
            lights:
              - "in some light"
            treatments:
              - "some treatment"
        """)
        #expect(corpus.curated == ["one, with a comma", "two without quotes"])
        #expect(corpus.palettes.count == 1)
        #expect(corpus.palettes[0].name == "Test")
        #expect(corpus.palettes[0].subjects == ["a subject"])
    }

    @Test("two palettes in one file are two palettes")
    func multiplePalettes() throws {
        // The flush-on-next-palette path: getting this wrong merges them, which reads as one huge
        // incoherent palette and reintroduces exactly the cross-category nonsense the grouping
        // exists to prevent.
        let corpus = try PromptCorpus.parse("""
        curated:
          - "x"
        palettes:
          - name: A
            subjects:
              - "a1"
            lights:
              - "l1"
            treatments:
              - "t1"
          - name: B
            subjects:
              - "b1"
              - "b2"
            lights:
              - "l2"
            treatments:
              - "t2"
        """)
        #expect(corpus.palettes.map(\.name) == ["A", "B"])
        #expect(corpus.palettes[1].subjects == ["b1", "b2"])
    }

    @Test("a malformed file throws with a line number rather than loading half of itself")
    func malformedFilesThrow() {
        func reason(_ text: String) -> PromptCorpus.CorpusError? {
            do { _ = try PromptCorpus.parse(text); return nil }
            catch let error as PromptCorpus.CorpusError { return error }
            catch { return nil }
        }

        #expect(reason("curated:\n  - \"x\"\n") == .empty("palettes"))
        #expect(reason("palettes:\n  - name: A\n    subjects:\n      - \"s\"\n    lights:\n      - \"l\"\n    treatments:\n      - \"t\"\n")
                == .empty("curated prompts"))
        // An axis left empty would compose nothing at all from that palette.
        #expect(reason("curated:\n  - \"x\"\npalettes:\n  - name: A\n    subjects:\n      - \"s\"\n    lights:\n    treatments:\n      - \"t\"\n")
                == .empty("lights in palette “A”"))
        #expect(reason("nonsense:\n  - \"x\"\n") == .malformed(line: 1, reason: "unknown key “nonsense”"))
        #expect(reason("curated:\n  - \"x\"\npalettes:\n  - name: A\n    colours:\n      - \"c\"\n")
                == .malformed(line: 5, reason: "unknown axis “colours”"))
        #expect(reason("curated:\n  - \"x\"\npalettes:\n  - \"not a palette\"\n")
                == .malformed(line: 4, reason: "a palette must start with “- name:”"))
        #expect(reason("  - \"orphan\"\n") == .malformed(line: 1, reason: "value before any key"))
    }

    @Test("a corpus for an unknown model falls back rather than leaving the button dead")
    func unknownModelFallsBack() throws {
        // A new checkpoint without its own prompts gets the house ones. Imperfect wording beats a
        // control that does nothing when tapped.
        let fallback = try PromptCorpus.load(forModel: "some-future-checkpoint")
        #expect(fallback == (try PromptCorpus.load(forModel: "sd15cn")))
        #expect(PromptCorpus.resourceName(forModel: "sd15cn") == "sd15cn_sampleprompts")
    }
}
