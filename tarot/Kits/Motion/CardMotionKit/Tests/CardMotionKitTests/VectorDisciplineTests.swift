import Foundation
import Testing
@testable import CardMotionKit

/// Source-scanning discipline: the kernel stays loop-less outside the primitive layer, and
/// free of clocks, system RNG, and platform imports. Every hard-won rule from the repo's
/// three prior implementations is applied:
///  * strip comments AND string literals before scanning (a doc comment or an error string
///    may name the banned things);
///  * match `\b(for|while|repeat)\b` ANYWHERE in a line — prefix matching missed inline and
///    labelled loops in froggo2 and citypigeon;
///  * the allowlist is keyed on the exact loop header and checked in BOTH directions (a stale
///    entry is blanket approval and fails);
///  * assert the file walk found files at all, or every test below passes vacuously;
///  * prove the matchers can fire, with violations shaped unlike the obvious ones.
@Suite("Vector discipline")
struct VectorDisciplineTests {

    // MARK: Source access

    static var sourcesURL: URL {
        // …/Tests/CardMotionKitTests/VectorDisciplineTests.swift → …/Sources/CardMotionKit
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/CardMotionKit")
    }

    static func kernelSources() throws -> [(name: String, text: String)] {
        let files = try FileManager.default.contentsOfDirectory(at: sourcesURL,
                                                                includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    /// The primitive layer: the files that ARE the allowed home of loops.
    static let primitiveLayer: Set<String> = ["Tensor.swift", "LaneNoise.swift"]

    /// Every legitimate loop outside the primitive layer, keyed on its exact header text,
    /// with the reason written down. Three legitimate categories exist in this repo:
    /// primitive kernels, bounded physical/algorithmic depth, and boundary marshalling.
    static let loopAllowlist: [(file: String, header: String, why: String)] = [
        ("MotionStep.swift", "for s in 0..<config.slotCount",
         "bounded physical depth: the spread slots, a bounded constant of the chosen layout " +
         "(froggo2's maxBounces category); appears twice — slot targeting and release choice"),
        ("MotionWorld.swift", "for (lane, position) in order.enumerated()",
         "boundary marshalling: the app hands one world its shuffle permutation"),
    ]

    static let bannedPatterns: [(pattern: String, why: String)] = [
        ("import SwiftUI", "a kernel that can import UI can grow presentation branches"),
        ("import UIKit", "same"),
        ("import AppKit", "same"),
        ("import Metal", "the GPU must never become authoritative here"),
        ("import MetalKit", "same"),
        ("import QuartzCore", "CACurrentMediaTime lives there — no clocks"),
        ("import simd", "simd_fast_* approximations break determinism"),
        ("import MLX", "MLX aborts in the iOS Simulator; this Kit exists to run everywhere"),
        ("import Accelerate", "another non-deterministic fast-math surface"),
        ("Date(", "no clocks — time arrives as dt from the caller"),
        ("Date.now", "no clocks"),
        ("CACurrentMediaTime", "no clocks"),
        ("DispatchTime", "no clocks"),
        (".random(", "system RNG mapping is implementation-defined; LaneNoise only"),
        ("arc4random", "system RNG"),
        ("drand48", "system RNG"),
        ("MLXRandom", "shape-dependent sequences break batch invariance (measured, citypigeon)"),
    ]

    // MARK: The scanner

    /// Remove line comments, (nested) block comments, and string literals, so scans see only
    /// code. String bodies become empty quotes; comment lines become empty lines (line
    /// structure is preserved for loop-header extraction).
    static func stripCommentsAndStrings(_ source: String) -> String {
        var out = String()
        out.reserveCapacity(source.count)
        var i = source.startIndex
        var blockDepth = 0
        var inLine = false
        var inString = false
        var inMultiline = false

        func peek(_ offset: Int) -> Character? {
            guard let idx = source.index(i, offsetBy: offset, limitedBy: source.index(before: source.endIndex))
            else { return nil }
            return source[idx]
        }

        while i < source.endIndex {
            let ch = source[i]
            if inLine {
                if ch == "\n" { inLine = false; out.append("\n") }
            } else if blockDepth > 0 {
                if ch == "/" && peek(1) == "*" {
                    blockDepth += 1
                    i = source.index(after: i)
                } else if ch == "*" && peek(1) == "/" {
                    blockDepth -= 1
                    i = source.index(after: i)
                } else if ch == "\n" {
                    out.append("\n")
                }
            } else if inMultiline {
                if ch == "\"" && peek(1) == "\"" && peek(2) == "\"" {
                    inMultiline = false
                    out.append("\"\"")   // leave an empty literal behind
                    i = source.index(i, offsetBy: 2)
                } else if ch == "\n" {
                    out.append("\n")
                }
            } else if inString {
                if ch == "\\" {
                    i = source.index(after: i)   // skip the escaped character
                } else if ch == "\"" {
                    inString = false
                    out.append("\"")
                }
            } else {
                if ch == "/" && peek(1) == "/" {
                    inLine = true
                    i = source.index(after: i)
                } else if ch == "/" && peek(1) == "*" {
                    blockDepth = 1
                    i = source.index(after: i)
                } else if ch == "\"" && peek(1) == "\"" && peek(2) == "\"" {
                    inMultiline = true
                    out.append("\"")
                    i = source.index(i, offsetBy: 2)
                } else if ch == "\"" {
                    inString = true
                    out.append("\"")
                } else {
                    out.append(ch)
                }
            }
            i = source.index(after: i)
        }
        return out
    }

    static let loopRegex = try! NSRegularExpression(pattern: #"\b(for|while|repeat)\b"#)

    static func loopLines(in stripped: String) -> [String] {
        stripped.components(separatedBy: "\n").filter { line in
            loopRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
        }.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: The gates

    @Test func kernelSourcesAreDiscoverable() throws {
        let sources = try Self.kernelSources()
        // If the path walk breaks, every test below passes vacuously and proves nothing.
        #expect(sources.count >= 5, "found only \(sources.map(\.name))")
        #expect(Set(sources.map(\.name)).isSuperset(of: Self.primitiveLayer))
    }

    @Test func noLoopsOutsideTheAllowlist() throws {
        for (name, text) in try Self.kernelSources() where !Self.primitiveLayer.contains(name) {
            let lines = Self.loopLines(in: Self.stripCommentsAndStrings(text))
            for line in lines {
                let allowed = Self.loopAllowlist.contains {
                    $0.file == name && line.contains($0.header)
                }
                #expect(allowed, "unallowlisted loop in \(name): \(line)")
            }
        }
    }

    /// The allowlist in the other direction: every entry must still match a real loop, or it
    /// has gone stale and become blanket approval.
    @Test func noStaleAllowlistEntries() throws {
        let sources = try Self.kernelSources()
        for entry in Self.loopAllowlist {
            let text = sources.first { $0.name == entry.file }?.text ?? ""
            let lines = Self.loopLines(in: Self.stripCommentsAndStrings(text))
            let found = lines.contains { $0.contains(entry.header) }
            #expect(found, "stale allowlist entry (\(entry.why)): \(entry.file): \(entry.header)")
        }
    }

    @Test func noBannedCallsAnywhereInTheKernel() throws {
        for (name, text) in try Self.kernelSources() {
            let stripped = Self.stripCommentsAndStrings(text)
            for (pattern, why) in Self.bannedPatterns {
                #expect(!stripped.contains(pattern), "\(name) contains \(pattern) — \(why)")
            }
        }
    }

    // MARK: Negative tests — a guard that never fires proves nothing.
    // The examples are deliberately shaped UNLIKE the obvious violation: inline after a
    // brace, labelled, mid-line — the shapes that escaped prefix matchers in froggo2 and
    // citypigeon before their detectors were fixed.

    @Test func theLoopMatcherActuallyFires() {
        let violations = [
            "if ready { for card in cards { move(card) } }",          // inline, not line-start
            "settle: repeat { tick() } while moving",                 // labelled repeat
            "let n = xs.reduce(0) { a, _ in a + 1 }; while n > 0 { }" // mid-line while
        ]
        for v in violations {
            #expect(!Self.loopLines(in: v).isEmpty, "matcher missed: \(v)")
        }
        // …and the stripper keeps it from firing on prose:
        let innocents = [
            "// a comment mentioning for and while and repeat",
            "let s = \"for example, while idle\"",
            "/* repeat after me */ let x = 1",
        ]
        for line in innocents {
            #expect(Self.loopLines(in: Self.stripCommentsAndStrings(line)).isEmpty,
                    "matcher false-positive on: \(line)")
        }
    }

    @Test func theBanMatcherActuallyFires() {
        let stripped = Self.stripCommentsAndStrings("let t0 = x + Date().timeIntervalSince1970")
        #expect(stripped.contains("Date("), "ban matcher missed a mid-line clock read")
        let hidden = Self.stripCommentsAndStrings("// don't ever call Date() here\nlet s = \"Date()\"")
        #expect(!hidden.contains("Date("), "ban matcher fires on comments/strings")
    }

    @Test func theStripperHandlesNestedBlockComments() {
        let src = "/* outer /* inner while */ still comment for */ let ok = 1"
        let stripped = Self.stripCommentsAndStrings(src)
        #expect(Self.loopLines(in: stripped).isEmpty, "nested block comment leaked: \(stripped)")
        #expect(stripped.contains("let ok = 1"))
    }

    /// Any `SomethingTests` cited in a kernel source comment must exist in this test target —
    /// phantom citations rot into false confidence (citypigeon wrote this audit after citing
    /// a test that did not exist yet).
    @Test func testsCitedInSourceCommentsExist() throws {
        let known: Set<String> = ["VectorDisciplineTests", "BatchInvarianceTests",
                                  "EmulationGateTests", "GoldenTrajectoryTests"]
        let regex = try NSRegularExpression(pattern: #"\b([A-Z][A-Za-z0-9]*Tests)\b"#)
        for (name, text) in try Self.kernelSources() {
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                let cited = String(text[Range(match.range(at: 1), in: text)!])
                #expect(known.contains(cited), "\(name) cites unknown suite \(cited)")
            }
        }
    }
}
