import XCTest
@testable import CityPigeon

/// Architectural invariants, enforced by scanning the source rather than asserted in prose.
///
/// Ported in spirit from froggo2's `VectorDisciplineTests`, and written because `Step.swift`'s own
/// doc comment claimed this file existed before it did — a claim a reader would reasonably have
/// trusted. A comment cannot stop someone adding a loop over entities or importing Metal into the
/// engine; a failing test can.
///
/// **Comments are stripped before scanning**, so documentation is free to name the very things that
/// are banned in code — as several doc comments in `Engine/` deliberately do.
final class VectorDisciplineTests: XCTestCase {

    private static let engineDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()          // CityPigeonTests
        .deletingLastPathComponent()          // citypigeon
        .appendingPathComponent("CityPigeon/Engine")

    private func engineSources() throws -> [(name: String, code: String)] {
        let urls = try FileManager.default
            .contentsOfDirectory(at: Self.engineDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(urls.count, 5, "engine sources not found at \(Self.engineDir.path)")
        return try urls.map { ($0.lastPathComponent, stripComments(try String(contentsOf: $0, encoding: .utf8))) }
    }

    /// Remove `//` line comments, `/* */` blocks, **and string literals**.
    ///
    /// Comments are stripped so documentation may freely name the things banned in code — several
    /// doc comments in `Engine/` deliberately do. String literals are stripped for the opposite
    /// reason: they are the inverse failure of everything else in this file. A future
    /// `throw Err("waiting for a free slot")` contains `\bfor\b` and would trip the loop guard with a
    /// message about a loop that does not exist. There is no such literal in `Engine/` today; this
    /// keeps it that way by construction rather than by luck.
    private func stripComments(_ s: String) -> String {
        var out = "", i = s.startIndex
        var inBlock = false, inString = false
        while i < s.endIndex {
            let rest = s[i...]
            if inBlock {
                if rest.hasPrefix("*/") { inBlock = false; i = s.index(i, offsetBy: 2) } else { i = s.index(after: i) }
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

    // MARK: - The boundary

    /// **The engine must not know how it is drawn.**
    ///
    /// The whole claim that `Render/` can be deleted and the engine still runs, tests and sweeps
    /// rests on this one line. It is also what lets a headless batch harness link `Engine/` alone.
    func testTheEngineImportsNothingPresentational() throws {
        let banned = ["Metal", "MetalKit", "SwiftUI", "UIKit", "AppKit", "QuartzCore", "simd"]
        for (name, code) in try engineSources() {
            for module in banned {
                XCTAssertFalse(code.contains("import \(module)"),
                               "\(name) imports \(module) — the engine has learned about "
                               + "presentation, and the Engine/Render boundary is gone")
            }
        }
    }

    // MARK: - Determinism

    /// One call to a system RNG makes a run unreproducible, and the failure is invisible until a
    /// replay diverges. Everything random goes through `Rng`, which is a pure function of
    /// `(seed, frame, stream, world, lane)`.
    func testTheEngineNeverReachesForTheSystemRandomGenerator() throws {
        let banned = ["Double.random", "Float.random", "Int.random", "Bool.random",
                      ".randomElement", ".shuffled", "arc4random", "SystemRandomNumberGenerator",
                      "MLXRandom"]
        for (name, code) in try engineSources() {
            for call in banned {
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
            for call in ["Date()", "CACurrentMediaTime", "DispatchTime.now", "mach_absolute_time"] {
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
    /// is not vectorized. A loop here would be a loop over worlds, payloads or targets, and it would
    /// silently undo the property the whole architecture is built on.
    func testTheStepKernelContainsNoLoops() throws {
        let code = try engineSources().first { $0.name == "Step.swift" }?.code
        let body = try XCTUnwrap(functionBody(named: "public static func advance", in: try XCTUnwrap(code)),
                                 "could not locate Step.advance")
        for (i, line) in body.split(separator: "\n").enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            XCTAssertFalse(containsLoopKeyword(t), "Step.advance line \(i) contains a loop: \(t)")
        }
    }

    /// Every other loop in the engine must be named here with a justification.
    ///
    /// The allowlist is keyed on the loop *header*, not the body, so changing what a loop does does
    /// not require re-approving it — but adding a loop, or changing what it iterates over, does.
    func testEveryEngineLoopIsJustified() throws {
        let allowed: [String: String] = [
            // Config-level analysis, not per-frame: enumerating the corners of the guarantee box.
            // Runs in tests and at startup, never inside the step.
            "for alt in [w.guaranteeAltitudeRange.lowerBound, w.guaranteeAltitudeRange.upperBound] {":
                "Spawn: worst-case corner enumeration over the guarantee box",
            "for vy in [w.guaranteeClimbRange.lowerBound, 0, w.guaranteeClimbRange.upperBound] {":
                "Spawn: same, the climb axis",

            // The odometer is host-side Double by design (Float32 cannot carry unbounded distance).
            // Runs once every `rebaseInterval` frames, outside `advance`.
            "for i in 0..<w.batch { w.odometer[i] += Double(shiftHost[i]) }":
                "Step.rebaseIfDue: host-side odometer accumulation, once per 1024 frames",
        ]

        var found: Set<String> = []
        for (name, code) in try engineSources() {
            for line in code.split(separator: "\n", omittingEmptySubsequences: false) {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard containsLoopKeyword(t) else { continue }
                XCTAssertNotNil(allowed[t],
                                "\(name) has an unjustified loop:\n    \(t)\n"
                                + "Add it to the allowlist with a written reason, or vectorize it. "
                                + "A loop over worlds or entities is almost certainly the latter.")
                found.insert(t)
            }
        }

        // Stale entries are as bad as missing ones: they make the list read as approval for code
        // that no longer exists.
        for (header, why) in allowed where !found.contains(header) {
            XCTFail("allowlist entry no longer matches any loop (\(why)):\n    \(header)")
        }
    }

    // MARK: - Comments must not name tests that do not exist

    /// **A doc comment that cites a test is making a checkable claim.**
    ///
    /// This file exists because `Step.swift` cited `VectorDisciplineTests` before it was written,
    /// and a reader — including me — would reasonably have trusted it. The same audit then turned up
    /// a second one: `Config.swift` cited `ConfigConsistencyTests`, which is froggo2's name for the
    /// suite that is called `ConfigDerivationTests` here. Neither was caught by anything; both were
    /// found only by going looking. So the audit is the test now.
    ///
    /// Cross-project citations are legitimate and must be declared, so that "this test is somewhere
    /// else" stays a deliberate statement rather than an unnoticed dangling reference.
    func testEveryTestNamedInSourceCommentsExists() throws {
        let external = [
            "SolverParityTests": "froggo2 — Kits/Sim CPU-vs-GPU parity suite, cited in Gate.swift",
        ]

        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        var declared = Set<String>()
        for url in try FileManager.default.contentsOfDirectory(at: testsDir, includingPropertiesForKeys: nil)
        where url.pathExtension == "swift" {
            let code = try String(contentsOf: url, encoding: .utf8)
            for m in matches(of: "(?:final class|class|func) ([A-Za-z_]+)", in: code) { declared.insert(m) }
        }
        XCTAssertGreaterThan(declared.count, 20, "could not enumerate the test suite")

        // Scan the ENGINE and RENDER sources, comments included — the point is the comments.
        var cited = Set<String>()
        for dir in ["CityPigeon/Engine", "CityPigeon/Render", "CityPigeon"] {
            let base = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(dir)
            let urls = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
            for url in urls where url.pathExtension == "swift" {
                let code = try String(contentsOf: url, encoding: .utf8)
                for m in matches(of: "([A-Za-z]+Tests|test[A-Z][A-Za-z]+)", in: code) { cited.insert(m) }
            }
        }

        for name in cited.sorted() where !declared.contains(name) {
            XCTAssertNotNil(external[name],
                            "a source comment cites `\(name)`, which does not exist in "
                            + "CityPigeonTests. Either write it, correct the name, or declare it as "
                            + "a cross-project reference in `external` above.")
        }
        for (name, why) in external where declared.contains(name) {
            XCTFail("`\(name)` is declared external (\(why)) but now also exists locally — "
                    + "the citation is ambiguous")
        }
    }

    /// Does this comment-stripped line contain a loop keyword **anywhere**, not merely at its start?
    ///
    /// Prefix matching was the original implementation and it was wrong: a negative check appended
    /// `func f() { for ghost in 0..<3 { _ = ghost } }` to the engine and the guard passed, because
    /// the trimmed line begins with `func`. Any loop sharing a line with other code — including one
    /// nested inside an `if` inside `Step.advance` — was invisible to the very test whose whole
    /// purpose is to find it.
    ///
    /// Word boundaries keep `forwardSpeed` and `.forEach` from matching.
    private func containsLoopKeyword(_ line: String) -> Bool {
        line.range(of: "\\b(for|while|repeat)\\b", options: .regularExpression) != nil
    }

    private func matches(of pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: 1))
        }
    }

    // MARK: - Helpers

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
