import XCTest

/// The architecture, enforced by a test rather than by a comment.
///
/// Two rules, both of which erode silently within weeks if nothing checks them:
///
///  1. **No loop over worlds, trajectories, entities or pairs in domain code.** Loops live in the
///     primitive kernels inside TensorKit and nowhere else. This is what makes batching free rather
///     than a rewrite, and it is why solving one level and validating four thousand candidate
///     levels are the same code path.
///
///  2. **No banned call anywhere in a Kit.** `simd_fast_*` is approximate by construction, a libm
///     transcendental is not correctly rounded and differs across OS versions, and anything reading
///     a clock or a random source destroys reproducibility outright.
///
/// Loops are legitimate in exactly three places, and each needs an allowlist entry stating which:
/// the primitive kernels; bounded physical or algorithmic depth (RK4 stages, portal recursion,
/// fixed-point relaxations — the analogue of torchsim's time loop); and marshalling at the boundary.
///
/// This is the same device as `kerfcalcTests.everyToolCitesAFormula`: the moat asserted by a test.
final class VectorDisciplineTests: XCTestCase {

    /// Files permitted to contain a loop, each with the reason it qualifies.
    private static let loopAllowlist: [String: String] = [
        // TensorKit — the primitive layer. Every loop in the codebase is supposed to be in here.
        "Tensor.swift": "the primitive kernels; this file IS the allowed place",
        "Trig.swift": "maps scalar kernels elementwise via Tensor.map",
        // DetMathKit — scalar kernels and fixed-iteration numerics.
        "DetMath.swift": "polynomial evaluation is inherently scalar",
        "DetMathDerived.swift": "fixed five Newton steps for cbrt; bounded, never convergence-driven",
        "DeterminismHash.swift": "byte-wise absorb, boundary marshalling",
        "Tick.swift": "no loops, present for completeness",
        // RelativityKit — bounded algorithmic depth.
        "Geodesic.swift": "the RK4 time loop: bounded step count, every trajectory advances together",
        "KerrMetric.swift": "no loops",
        "Regions.swift": "no loops",
        "Invariants.swift": "no loops",
        // PortalKit.
        "Portal.swift": "holonomy composes a bounded list of transforms",
        // StoryKit — boundary marshalling: YAML in, model out.
        "StoryGraph.swift": "graph traversal over a finite node set, reporting only",
        "StoryLoader.swift": "parsing is boundary marshalling",
    ]

    /// Calls that must not appear in any Kit source.
    private static let bannedCalls: [(pattern: String, why: String)] = [
        ("simd_fast_", "approximate by construction; use the simd_precise_ variant"),
        ("Foundation.sin(", "libm is not correctly rounded and varies by OS; use DetMath"),
        ("Foundation.cos(", "libm is not correctly rounded and varies by OS; use DetMath"),
        ("Date()", "a clock in the simulation destroys reproducibility"),
        ("Date.now", "a clock in the simulation destroys reproducibility"),
        (".random(", "unseeded randomness cannot be replayed"),
        ("arc4random", "unseeded randomness cannot be replayed"),
        ("import Metal", "a Kit that can import Metal can make the GPU authoritative"),
        ("import SwiftUI", "a Kit that can import SwiftUI can let a frame time reach the sim"),
        ("import SpriteKit", "presentation must not be reachable from the simulation core"),
        ("import MLX", "no ML in the authoritative path"),
    ]

    private var kitsRoot: URL {
        // .../Kits/Relativity/RelativityKit/Tests/RelativityKitTests/ThisFile.swift → .../Kits
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func kitSources() throws -> [URL] {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: kitsRoot, includingPropertiesForKeys: nil) else { return [] }
        return e.compactMap { $0 as? URL }.filter {
            $0.pathExtension == "swift"
                && $0.path.contains("/Sources/")     // sources only; tests may loop freely
                && !$0.path.contains("/.build/")
        }
    }

    func testKitSourcesAreDiscoverable() {
        // If the path walk breaks, both tests below pass vacuously and prove nothing. Guard it.
        let files = (try? kitSources()) ?? []
        XCTAssertGreaterThanOrEqual(files.count, 8,
                                    "expected to find the Kit sources under \(kitsRoot.path)")
    }

    func testNoLoopsOutsideTheAllowlist() throws {
        var offenders: [String] = []
        for url in try kitSources() {
            let name = url.lastPathComponent
            let text = try String(contentsOf: url, encoding: .utf8)
            for (n, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard !line.hasPrefix("//"), !line.hasPrefix("///") else { continue }
                let hasLoop = line.contains("for ") && line.contains(" in ")
                    || line.hasPrefix("while ") || line.contains(" while ")
                guard hasLoop else { continue }
                if Self.loopAllowlist[name] == nil {
                    offenders.append("\(name):\(n + 1)  \(line)")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            Loop found in domain code. Express it as tensor algebra, or add the file to
            loopAllowlist with a stated justification:
            \(offenders.joined(separator: "\n"))
            """)
    }

    func testNoBannedCallsInAnyKit() throws {
        var offenders: [String] = []
        for url in try kitSources() {
            let name = url.lastPathComponent
            let text = try String(contentsOf: url, encoding: .utf8)
            for (n, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard !line.hasPrefix("//"), !line.hasPrefix("///") else { continue }
                for (pattern, why) in Self.bannedCalls where line.contains(pattern) {
                    offenders.append("\(name):\(n + 1)  '\(pattern)' — \(why)")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, "banned calls:\n\(offenders.joined(separator: "\n"))")
    }

    func testTheDisciplineTestActuallyDetectsAViolation() {
        // A guard that never fires proves nothing. This is the check that the check works: feed it
        // a line that should be rejected and confirm the matcher rejects it.
        let violating = "for trajectory in trajectories { advance(trajectory) }"
        XCTAssertTrue(violating.contains("for ") && violating.contains(" in "),
                      "the loop matcher must catch an obvious per-entity loop")
        let banned = "let n = simd_fast_normalize(v)"
        XCTAssertTrue(Self.bannedCalls.contains { banned.contains($0.pattern) },
                      "the ban matcher must catch simd_fast_normalize")
    }
}
