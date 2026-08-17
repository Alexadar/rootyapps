import Testing
import Foundation

/// The architectural rule, enforced rather than documented.
///
/// The whole game is written as batch mathematics so that batching worlds later is free. That only
/// holds if nobody quietly reintroduces a loop over rooftops or over pairs — and "nobody" includes
/// me, six weeks from now, adding one line to fix something. A comment cannot stop that; a failing
/// test can.
///
/// So: every `for` and `while` in the Kit is accounted for here. Loops are legitimate in exactly
/// three places, and each allowance names its reason:
///
///  * **the primitive layer** — `Tensor` and `SplitMix64` *are* the vector kernels; the loops inside
///    them are the implementation of elementwise arithmetic, and having them there once is the whole
///    point of having them nowhere else;
///  * **bounded physical or algorithmic depth** — two bounce sub-arcs, two fixed-point passes, K
///    flood relaxations. These are the analogue of the time loop in
///    `monstro_shooter.swift/torchsim/env_torch.py`, the one loop that doctrine explicitly permits;
///  * **marshalling at the boundary** — packing `[CityBlock]` into tensors, or reading a route back
///    out for the UI. Data crossing in or out of the vector world, never game logic inside it.
///
/// A new loop that is none of these fails this test, and the fix is to express it as tensor algebra
/// or to add it here with a justification that survives being read aloud.
@Suite("Vector discipline")
struct VectorDisciplineTests {

    /// Files that ARE the vector primitives. Loops here are the kernels themselves.
    static let primitiveLayer: Set<String> = ["Tensor.swift", "SplitMix64.swift"]

    /// Every permitted loop outside the primitive layer, with the reason it is allowed.
    static let allowed: [String: [String: String]] = [
        "Ballistics.swift": [
            "for i in 1...w.maxBounces":
                "bounded physical constant (2 sub-arcs), not a loop over entities",
        ],
        "BatchSolver.swift": [
            "for (wi, block) in blocks.enumerated()":
                "marshalling [CityBlock] into tensors at the boundary",
            "for (si, roof) in block.rooftops.enumerated() where si < k":
                "marshalling, inside the same pack",
            "for pass in 0..<2":
                "fixed-point passes over the landing inset; a constant, not a convergence loop",
            "for _ in 0..<k":
                "flood-fill relaxation depth — the algorithm's depth, like torchsim's time loop",
            "for step in 1...k":
                "same flood, recording the depth at which each rooftop is first reached",
        ],
        "ReachabilityGraph.swift": [
            "for (i, r) in block.rooftops.enumerated()":
                "building the id↔slot map; marshalling",
            "while distances[node] > 0":
                "walking one already-known shortest route back for the UI; bounded by par",
        ],
        "BlockGenerator.swift": [
            "for attempt in 0..<maxAttempts":
                "bounded resampling of whole districts, not a loop over their contents",
            // Was invisible to the original prefix-based detector because the line starts with the
            // label `repairLoop:`, not with `while`. It is a legitimate loop — but it went
            // unaudited from the day it was written until the detector was fixed, which is the
            // clearest evidence that "the guard passes" and "the guard looked" are different claims.
            "while true":
                "repair iterations on ONE district, bounded by maxRepairs and exited by the verdict; "
                + "not a loop over rooftops or pairs",
            "for candidate in generatePool":
                "walking already-graded survivors to take the first; the grading itself was one "
                + "batched pass over the whole pool",
        ],
        "Reachability.swift": [
            "for o in obstacles where o.id != a.id && o.id != b.id":
                "line-of-flight check; deliberately NOT on the solver path, used only to verify the "
                + "no-intervening-tower assumption in tests",
            "for d in [Swift.max(span.lowerBound, 0), Swift.min(span.upperBound, landing)]":
                "two endpoint evaluations, justified by the arc's concavity",
        ],
        "Geometry.swift": [
            "while d > .pi":
                "angle unwrapping in a reporting-only helper",
            "while d < -.pi":
                "angle unwrapping in a reporting-only helper",
            "for (origin, dir, lo, hi) in [(p.x, d.x, minX, maxX), (p.z, d.z, minZ, maxZ)]":
                "two axes of a slab test, in the test-only line-of-flight helper",
        ],
    ]


    // MARK: - Finding loops
    //
    // Loops are found by scanning for the KEYWORD ANYWHERE in a line, not by testing whether a line
    // begins with one. The first version of this file matched `line.hasPrefix("for ")`, which sees
    // only loops that start a line — so
    //
    //     func f(_ xs: [Int]) -> Int { var t = 0; for x in xs { t += x }; return t }
    //
    // was completely invisible to it, and, worse, invisible to `adjacencyIsPurelyElementwise`, the
    // one check whose whole purpose is to find loops in a specific function. It passed green.
    //
    // All four of the negative tests written to validate these guards happened to use violations
    // that began a line, so every one of them confirmed a detector that had this hole rather than
    // exposing it. A negative test only proves what its example exercises. (Found by the citypigeon
    // session hitting the identical bug in its own engine.)

    /// A loop found in a source file: its header, from the keyword up to the opening brace.
    struct FoundLoop {
        let line: Int
        let header: String
        let raw: String
    }

    /// Strip line comments and string literals, so neither prose nor an error message can look like
    /// a loop. Doc comments have to be able to discuss `for` freely — this file is full of that.
    private static func stripped(_ line: String) -> String {
        var s = line
        if let r = s.range(of: "//") { s = String(s[s.startIndex..<r.lowerBound]) }
        while let start = s.firstIndex(of: "\""),
              let end = s[s.index(after: start)...].firstIndex(of: "\"") {
            s.replaceSubrange(start...end, with: "")
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    static func loops(in source: String) -> [FoundLoop] {
        // Word boundaries keep `forwardSpeed`, `.forEach` and `whileCondition` from tripping this.
        let keyword = try! NSRegularExpression(pattern: #"\b(for|while|repeat)\b"#)
        var found: [FoundLoop] = []

        for (i, rawLine) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = stripped(String(rawLine))
            guard !line.isEmpty else { continue }
            for m in keyword.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                guard let r = Range(m.range, in: line) else { continue }
                let tail = line[r.lowerBound...]
                let header = String(tail.prefix(while: { $0 != "{" })).trimmingCharacters(in: .whitespaces)
                found.append(FoundLoop(line: i + 1, header: header,
                                       raw: line.trimmingCharacters(in: .whitespaces)))
            }
        }
        return found
    }

    private static var sourceDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // ReachabilityKitTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // package root
            .appendingPathComponent("Sources/ReachabilityKit")
    }

    @Test("every loop outside the primitive layer is accounted for")
    func noUnjustifiedLoops() throws {
        let files = try FileManager.default
            .contentsOfDirectory(at: Self.sourceDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty, "found no sources to audit at \(Self.sourceDirectory.path)")

        for file in files {
            let name = file.lastPathComponent
            guard !Self.primitiveLayer.contains(name) else { continue }

            let source = try String(contentsOf: file, encoding: .utf8)
            let permitted = Self.allowed[name] ?? [:]

            for loop in Self.loops(in: source) {
                // Compare loop HEADERS only — keyword up to the opening brace — so a change to a
                // loop's body never silently invalidates its justification.
                let isAllowed = permitted.keys.contains {
                    loop.header.hasPrefix($0) || $0.hasPrefix(loop.header)
                }
                #expect(isAllowed, """
                    \(name):\(loop.line) contains an unaccounted-for loop:
                        \(loop.header)
                    (full line: \(loop.raw))
                    Express it as tensor algebra, or add it to `allowed` with the reason it is not \
                    a loop over worlds, rooftops or pairs.
                    """)
            }
        }
    }

    /// The allowlist must not rot into blanket approval.
    ///
    /// The check above only asks "is every loop I found permitted?" — which means a justification
    /// can outlive the loop it was written for. Delete a loop, leave its entry behind, and the list
    /// slowly becomes a list of things that *used* to be fine. Then someone adds a new loop whose
    /// header happens to match a stale entry and it sails through.
    ///
    /// So the relation is checked in both directions: every allowlisted loop must still exist.
    /// (Borrowed from the equivalent test in the citypigeon session, which had this guard when this
    /// one did not.)
    @Test("no allowlist entry outlives the loop it justifies")
    func allowlistHasNoStaleEntries() throws {
        for (file, entries) in Self.allowed {
            let url = Self.sourceDirectory.appendingPathComponent(file)
            guard let source = try? String(contentsOf: url, encoding: .utf8) else {
                Issue.record("allowlist names \(file), which no longer exists")
                continue
            }
            let headers = Self.loops(in: source).map(\.header)

            for entry in entries.keys {
                let stillThere = headers.contains { $0.hasPrefix(entry) || entry.hasPrefix($0) }
                #expect(stillThere, """
                    \(file) allowlists a loop that is no longer there:
                        \(entry)
                    Remove the entry. A justification kept past its loop widens what the next one \
                    is allowed to be.
                    """)
            }
        }
    }

    @Test("the solver's hot path never loops over pairs")
    func adjacencyIsPurelyElementwise() throws {
        // The specific thing that must never come back: `for a in roofs { for b in roofs { ... } }`.
        // The adjacency builder is where that shape would reappear first, so it is checked directly.
        let file = Self.sourceDirectory.appendingPathComponent("BatchSolver.swift")
        let source = try String(contentsOf: file, encoding: .utf8)

        guard let start = source.range(of: "public static func adjacency"),
              let end = source.range(of: "// MARK: - Graph questions") else {
            Issue.record("could not locate the adjacency builder")
            return
        }
        let body = String(source[start.lowerBound..<end.lowerBound])

        let headers = Self.loops(in: body).map(\.header)

        // Exactly one loop is permitted in there: the two-pass inset fixed point. Equality rather
        // than a subset check, so a slice that captured too much fails too — and the scan is
        // keyword-anywhere, so a loop written inline inside an `if` cannot slip past by not
        // starting its line.
        #expect(headers == ["for pass in 0..<2"],
                "adjacency contains unexpected loops: \(headers)")
    }
}
