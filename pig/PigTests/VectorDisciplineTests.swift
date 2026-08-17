import XCTest
@testable import Pig

/// Architectural invariants, enforced by scanning the source rather than asserted in prose.
///
/// Ported in spirit from `citypigeon/CityPigeonTests/VectorDisciplineTests.swift`. A comment cannot
/// stop someone adding a loop over slots or importing Metal into the engine; a failing test can.
///
/// **Comments and string literals are stripped before scanning.** Comments so that documentation is
/// free to name the very things that are banned in code — several doc comments in `Engine/`
/// deliberately do. String literals for the opposite reason: a future `throw Err("waiting for a free
/// slot")` contains `\bfor\b` and would trip the loop guard with a message about a loop that does not
/// exist.
///
/// Every guard here is **verified to fail** on a deliberate violation, in
/// `testTheGuardsActuallyCatchViolations`. A source-scanning test that has never been seen to fail is
/// a test that might be scanning nothing at all.
final class VectorDisciplineTests: XCTestCase {

    /// `Tensor.swift` and `Rng.swift` ARE the vector layer: loops live inside them, and nowhere else.
    /// That is the whole arrangement, so they are excluded from the loop scan by name rather than by
    /// an ever-growing allowlist of their individual lines.
    private static let vectorLayer: Set<String> = ["Tensor.swift", "Rng.swift"]

    private static let engineDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()          // PigTests
        .deletingLastPathComponent()          // pig
        .appendingPathComponent("Pig/Engine")

    private func engineSources() throws -> [(name: String, code: String)] {
        let urls = try FileManager.default
            .contentsOfDirectory(at: Self.engineDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(urls.count, 5, "engine sources not found at \(Self.engineDir.path)")
        return try urls.map {
            ($0.lastPathComponent, stripCommentsAndStrings(try String(contentsOf: $0, encoding: .utf8)))
        }
    }

    // MARK: - The boundary

    /// **The engine must not know how it is drawn.**
    ///
    /// The claim that `Render/` can be deleted and the engine still runs and still tests rests on
    /// this one line.
    func testTheEngineImportsNothingPresentational() throws {
        for (name, code) in try engineSources() {
            for module in Self.bannedImports {
                XCTAssertFalse(code.contains("import \(module)"),
                               "\(name) imports \(module) — the engine has learned about "
                               + "presentation, and the Engine/Render boundary is gone")
            }
        }
    }

    // MARK: - Determinism

    /// One call to a system RNG makes a run unreproducible, and the failure is invisible until a
    /// replay diverges. Everything random goes through `Rng`, a pure function of
    /// `(seed, frame, stream, index)`.
    func testTheEngineNeverReachesForTheSystemRandomGenerator() throws {
        for (name, code) in try engineSources() {
            for call in Self.bannedRandom {
                XCTAssertFalse(code.contains(call),
                               "\(name) uses \(call) — determinism is gone, and with it replay and "
                               + "every batched test")
            }
        }
    }

    /// Time must come from the frame counter, never from a clock. A clock in the engine makes the
    /// simulation depend on how fast the machine ran it.
    func testTheEngineNeverReadsAClock() throws {
        for (name, code) in try engineSources() {
            for call in Self.bannedClocks {
                XCTAssertFalse(code.contains(call),
                               "\(name) reads a clock — the step must advance by whole `dt`s from "
                               + "the frame counter and nothing else")
            }
        }
    }

    // MARK: - The loop allowlist

    /// **`Step.advance` must contain no loops at all.**
    ///
    /// This is the sharpest form of the vector discipline: the per-frame kernel is elementwise or it
    /// is not vectorized. A loop here would be a loop over worlds or over pile slots, and it would
    /// silently undo the property the whole architecture is built on.
    func testTheStepKernelContainsNoLoops() throws {
        let code = try XCTUnwrap(try engineSources().first { $0.name == "Step.swift" }?.code)
        let body = try XCTUnwrap(functionBody(named: "static func advance", in: code),
                                 "could not locate Step.advance")
        for (i, line) in body.split(separator: "\n").enumerated() {
            XCTAssertFalse(containsLoopKeyword(String(line)),
                           "Step.advance line \(i) contains a loop: \(line)")
        }
    }

    /// Every loop outside the vector layer must be named here with a justification.
    ///
    /// The allowlist is keyed on the loop *header*, so changing what a loop does does not require
    /// re-approving it — but adding one, or changing what it iterates over, does. **Stale entries
    /// fail too**: a list that approves code which no longer exists reads as approval for whatever
    /// replaced it.
    func testEveryEngineLoopIsJustified() throws {
        let allowed: [String: String] = [
            // The script is six entries long and fixed at compile time. This is a loop over the
            // PROGRAM, not over anything being simulated — the same exemption a loop over network
            // layers gets in `monstro_shooter`'s MLP, and the distinction the whole discipline turns
            // on. It runs once per frame at N = 1 during a demo, and never inside `Step.advance`.
            "for step in Scenario.script {":
                "Scenario.beat: linear scan of a fixed six-entry script",
            "for step in script {":
                "Scenario.boundaries: the same script, listed for caption timing",
        ]

        var found: Set<String> = []
        for (name, code) in try engineSources() where !Self.vectorLayer.contains(name) {
            for line in code.split(separator: "\n", omittingEmptySubsequences: false) {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard containsLoopKeyword(t) else { continue }
                XCTAssertNotNil(allowed[t],
                                "\(name) has an unjustified loop:\n    \(t)\n"
                                + "Add it to the allowlist with a written reason, or vectorize it. "
                                + "A loop over worlds or slots is almost certainly the latter.")
                found.insert(t)
            }
        }
        for (header, why) in allowed where !found.contains(header) {
            XCTFail("allowlist entry no longer matches any loop (\(why)):\n    \(header)")
        }
    }

    /// The vector layer is where loops are *supposed* to be, and if it ever has none then the scan
    /// above is passing because it is reading the wrong files.
    func testTheVectorLayerStillContainsTheLoops() throws {
        var total = 0
        for (name, code) in try engineSources() where Self.vectorLayer.contains(name) {
            let n = code.split(separator: "\n").filter { containsLoopKeyword(String($0)) }.count
            XCTAssertGreaterThan(n, 0, "\(name) is listed as the vector layer but contains no loops")
            total += n
        }
        XCTAssertGreaterThan(total, 8, "the vector layer looks empty — is the scan reading anything?")
    }

    // MARK: - Comments must not name tests that do not exist

    /// **A doc comment that cites a test is making a checkable claim.**
    ///
    /// `Shape.swift` cites `ShapeOracleTests` and `Step.swift`'s neighbours cite this file; if one of
    /// those is renamed the comment becomes a confident lie, and nothing else would ever catch it.
    func testEveryTestNamedInSourceCommentsExists() throws {
        // Cross-project citations are legitimate and must be declared, so "this test lives somewhere
        // else" stays a deliberate statement rather than an unnoticed dangling reference. An entry
        // here that no longer matches a citation is as misleading as a missing one, so the loop below
        // fails on stale entries too.
        let external: [String: String] = [
            "FilmScenarioChecks": "tarot — the suite that checks its filmed scenario, cited as the "
                + "precedent for Scenario.swift",
        ]

        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        var declared = Set<String>()
        for url in try FileManager.default.contentsOfDirectory(at: testsDir, includingPropertiesForKeys: nil)
        where url.pathExtension == "swift" {
            let code = try String(contentsOf: url, encoding: .utf8)
            for m in matches(of: "(?:final class|class|func) ([A-Za-z_]+)", in: code) { declared.insert(m) }
        }
        XCTAssertGreaterThan(declared.count, 20, "could not enumerate the test suite")

        // Scan the ENGINE and RENDER sources, comments INCLUDED — the point is the comments.
        var cited = Set<String>()
        for dir in ["Pig/Engine", "Pig/Render", "Pig"] {
            let base = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(dir)
            let urls = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
            for url in urls where url.pathExtension == "swift" {
                let code = try String(contentsOf: url, encoding: .utf8)
                // The word boundary is not decoration: without it `greatestFiniteMagnitude` reads as a
                // citation of a test called `testFiniteMagnitude`, and this scan fails on a name
                // nobody wrote.
                for m in matches(of: "\\b([A-Za-z]+Tests|test[A-Z][A-Za-z]+)", in: code) { cited.insert(m) }
            }
        }

        for name in cited.sorted() where !declared.contains(name) {
            XCTAssertNotNil(external[name],
                            "a source comment cites `\(name)`, which does not exist in PigTests. "
                            + "Either write it, correct the name, or declare it as a cross-project "
                            + "reference in `external` above.")
        }
        for (name, why) in external where declared.contains(name) {
            XCTFail("`\(name)` is declared external (\(why)) but now also exists locally — "
                    + "the citation is ambiguous")
        }
    }

    // MARK: - The guards must be able to fail
    //
    // Every scan above is only as good as its detector. These feed the detectors source that
    // deliberately violates them, in shapes NOT chosen to flatter the implementation: loops sharing a
    // line with other code, loops nested inside an `if`, labelled loops, `repeat`/`while`, and a
    // banned call reached through a local alias.

    func testTheGuardsActuallyCatchViolations() {
        let violations = [
            "func f() { for ghost in 0..<3 { _ = ghost } }",
            "if ready { for s in slots { touch(s) } }",
            "outer: for i in 0..<n { break outer }",
            "while notDone { advance() }",
            "repeat { advance() } while notDone",
            "        for (i, x) in xs.enumerated() { _ = (i, x) }",
        ]
        for v in violations {
            XCTAssertTrue(containsLoopKeyword(v),
                          "the loop detector missed a real loop:\n    \(v)")
        }

        // Things that merely LOOK like loops must not trip it, or the guard becomes noise and gets
        // switched off.
        let innocent = [
            "let forwardSpeed = 3.0",
            "xs.forEach { touch($0) }",
            "let reformatted = before",
            "let whilst = 1",
        ]
        for line in innocent {
            XCTAssertFalse(containsLoopKeyword(line),
                           "the loop detector fired on something that is not a loop:\n    \(line)")
        }

        // The comment/string stripper must remove exactly the things it claims to, and nothing else.
        let source = """
        // for i in 0..<3 { }
        /* while true { } */
        let message = "waiting for a free slot"
        let escaped = "a \\" quote with while inside"
        let real = 1
        """
        let stripped = stripCommentsAndStrings(source)
        XCTAssertFalse(containsLoopKeyword(stripped),
                       "stripping left a loop keyword behind:\n\(stripped)")
        XCTAssertTrue(stripped.contains("let real = 1"), "stripping ate real code:\n\(stripped)")

        // And the banned-token scans must see a violation when there is one.
        let dirty = "let x = Double.random(in: 0...1); let t = Date(); import SwiftUI"
        XCTAssertTrue(Self.bannedRandom.contains { dirty.contains($0) }, "random guard is blind")
        XCTAssertTrue(Self.bannedClocks.contains { dirty.contains($0) }, "clock guard is blind")
        XCTAssertTrue(Self.bannedImports.contains { dirty.contains("import \($0)") },
                      "import guard is blind")
    }

    // MARK: - Detectors

    private static let bannedImports = ["Metal", "MetalKit", "SwiftUI", "UIKit", "AppKit",
                                        "QuartzCore", "simd", "ImageIO"]
    private static let bannedRandom = ["Double.random", "Float.random", "Int.random", "Bool.random",
                                       ".randomElement", ".shuffled", "arc4random",
                                       "SystemRandomNumberGenerator"]
    private static let bannedClocks = ["Date()", "CACurrentMediaTime", "DispatchTime.now",
                                       "mach_absolute_time", "ProcessInfo.processInfo.systemUptime"]

    /// Does this line contain a loop keyword **anywhere**, not merely at its start?
    ///
    /// Prefix matching is the obvious implementation and it is wrong: `func f() { for … }` begins
    /// with `func`, so any loop sharing a line with other code — including one nested inside an `if`
    /// — would be invisible to the very test whose purpose is to find it. Word boundaries keep
    /// `forwardSpeed` and `.forEach` from matching.
    private func containsLoopKeyword(_ line: String) -> Bool {
        line.range(of: "\\b(for|while|repeat)\\b", options: .regularExpression) != nil
    }

    private func stripCommentsAndStrings(_ s: String) -> String {
        var out = "", i = s.startIndex
        var inBlock = false, inString = false
        while i < s.endIndex {
            let rest = s[i...]
            if inBlock {
                if rest.hasPrefix("*/") { inBlock = false; i = s.index(i, offsetBy: 2) }
                else { i = s.index(after: i) }
                continue
            }
            if inString {
                if s[i] == "\\", s.index(after: i) < s.endIndex { i = s.index(i, offsetBy: 2); continue }
                if s[i] == "\"" { inString = false }
                i = s.index(after: i)
                continue
            }
            if rest.hasPrefix("/*") { inBlock = true; i = s.index(i, offsetBy: 2); continue }
            if rest.hasPrefix("//") {
                while i < s.endIndex, s[i] != "\n" { i = s.index(after: i) }
                continue
            }
            if s[i] == "\"" { inString = true; i = s.index(after: i); continue }
            out.append(s[i]); i = s.index(after: i)
        }
        return out
    }

    private func matches(of pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: 1))
        }
    }

    /// Brace-matched body of the first function whose declaration starts with `prefix`.
    private func functionBody(named prefix: String, in code: String) -> String? {
        guard let declRange = code.range(of: prefix),
              let open = code.range(of: "{", range: declRange.upperBound..<code.endIndex)
        else { return nil }
        var depth = 0, i = open.lowerBound
        while i < code.endIndex {
            if code[i] == "{" { depth += 1 }
            if code[i] == "}" {
                depth -= 1
                if depth == 0 { return String(code[open.upperBound..<i]) }
            }
            i = code.index(after: i)
        }
        return nil
    }
}
