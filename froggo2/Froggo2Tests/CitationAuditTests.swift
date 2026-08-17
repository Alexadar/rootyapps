import XCTest

/// Comments that name a test must name a test that exists.
///
/// This exists because it happened. The citypigeon session's `Step.swift` carried the sentence
/// *"`VectorDisciplineTests` enforces that by scanning the source, so the property survives future
/// edits"* — and there was no such suite. It had been promised in a plan, asserted in a comment, and
/// never written. Nobody would have gone looking, because the comment was the thing you would have
/// checked.
///
/// The froggo2 tree came back clean when the same audit was run by hand, but "clean today" is not a
/// property that survives editing, so it is a test now.
///
/// The design problem is that grep cannot tell a **phantom** from a **cross-project citation**.
/// Comments here legitimately point at other apps in the monorepo — that is how the house patterns
/// get carried between them, and stripping those references would make the code less honest, not
/// more. So a cited name must either be declared locally, or be listed in `external` with the
/// project it belongs to. The list also fails in the opposite direction: if an external name later
/// becomes locally declared, the citation has turned ambiguous and this says so.
final class CitationAuditTests: XCTestCase {

    /// Test names cited on purpose that live in another project. Name the project, so the reader of
    /// the comment can find it.
    /// (Currently empty — froggo2 cites other projects by file path rather than by suite name.
    /// The mechanism is here so that adding such a citation is a deliberate, attributed act.)
    static let external: [String: String] = [:]

    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private var sourceRoots: [URL] {
        [
            root.appendingPathComponent("Froggo2"),
            root.appendingPathComponent("Kits/Reachability/ReachabilityKit/Sources"),
            root.appendingPathComponent("Kits/Sim/FroggoSim/Sources"),
        ]
    }

    private var testRoots: [URL] {
        [
            root.appendingPathComponent("Froggo2Tests"),
            root.appendingPathComponent("Kits/Reachability/ReachabilityKit/Tests"),
            root.appendingPathComponent("Kits/Sim/FroggoSim/Tests"),
        ]
    }

    private func swiftFiles(under roots: [URL]) -> [URL] {
        roots.flatMap { root -> [URL] in
            guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
            else { return [] }
            return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        }
    }

    /// Every `SomethingTests` declared anywhere in the test targets.
    private func locallyDeclaredSuites() throws -> Set<String> {
        var found: Set<String> = []
        let pattern = try NSRegularExpression(pattern: #"(?:struct|final class|class)\s+([A-Z][A-Za-z0-9]*Tests)\b"#)
        for file in swiftFiles(under: testRoots) {
            let s = try String(contentsOf: file, encoding: .utf8)
            for m in pattern.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
                if let r = Range(m.range(at: 1), in: s) { found.insert(String(s[r])) }
            }
        }
        return found
    }

    func testEveryTestNamedInSourceCommentsExists() throws {
        let declared = try locallyDeclaredSuites()
        XCTAssertFalse(declared.isEmpty, "found no test suites at all — the audit would pass vacuously")

        let cited = try NSRegularExpression(pattern: #"\b([A-Z][A-Za-z0-9]*Tests)\b"#)
        for file in swiftFiles(under: sourceRoots) {
            let source = try String(contentsOf: file, encoding: .utf8)
            let name = file.lastPathComponent
            var seen: Set<String> = []

            for m in cited.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                guard let r = Range(m.range(at: 1), in: source) else { continue }
                let suite = String(source[r])
                guard seen.insert(suite).inserted else { continue }

                if let project = Self.external[suite] {
                    XCTAssertFalse(declared.contains(suite), """
                        \(name) cites `\(suite)` as belonging to \(project), but a suite of that name \
                        is now declared locally too. The citation is ambiguous — rename one, or drop \
                        the `external` entry.
                        """)
                    continue
                }

                XCTAssertTrue(declared.contains(suite), """
                    \(name) cites `\(suite)`, which is not declared in any test target. Either write \
                    it, correct the name, or declare it in `external` above as a cross-project \
                    reference with the project it belongs to.
                    """)
            }
        }
    }
}
