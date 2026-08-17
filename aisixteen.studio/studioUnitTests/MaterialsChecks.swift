import XCTest
@testable import Studio

/// Keeps the pre-Liquid-Glass materials out of the app.
///
/// The handoff bans `.ultraThinMaterial`, `.regularMaterial` and `.thinMaterial` outright, and the
/// legacy build in `aisixteen.studio.old/` is made of them — so this is not a hypothetical rule, it
/// is the exact thing that would creep back in if a screen were ported rather than rebuilt.
///
/// ⚠️ A source-scanning guard that has never been seen to fail is not a guard. `testTheDetector…`
/// below feeds it violations shaped **unlike** the ones in the app — inside interpolation, after a
/// label, on a continued line — and requires it to catch every one.
final class MaterialsChecks: XCTestCase {

    static let banned = ["ultraThinMaterial", "regularMaterial", "thinMaterial",
                         "thickMaterial", "ultraThickMaterial", "bar.material"]

    func testNoSourceFileUsesAPreLiquidGlassMaterial() throws {
        let sources = try Self.swiftFiles(in: Self.appSourceRoot)
        XCTAssertGreaterThan(sources.count, 15, "the scan found almost nothing — wrong root?")

        var offenders: [String] = []
        for url in sources {
            let text = try String(contentsOf: url, encoding: .utf8)
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                guard let hit = Self.violation(in: String(line)) else { continue }
                offenders.append("\(url.lastPathComponent):\(number + 1) — \(hit)")
            }
        }
        XCTAssertEqual(offenders, [], "banned materials:\n\(offenders.joined(separator: "\n"))")
    }

    func testGlassIsAppliedOnlyThroughTheOneModifier() throws {
        // Every glass surface goes through `stGlass`, because Reduce Transparency has to change the
        // material everywhere and a single bare call site ships a screen that ignores the setting.
        let sources = try Self.swiftFiles(in: Self.appSourceRoot)
        var offenders: [String] = []

        for url in sources where url.lastPathComponent != "GlassTreatments.swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let stripped = Self.stripping(comments: String(line))
                guard stripped.contains(".glassEffect(") else { continue }
                offenders.append("\(url.lastPathComponent):\(number + 1)")
            }
        }
        XCTAssertEqual(offenders, [],
                       "bare .glassEffect outside GlassTreatments.swift:\n\(offenders.joined(separator: "\n"))")
    }

    // MARK: The guard can fail

    func testTheDetectorCatchesViolationsShapedUnlikeTheOnesInTheApp() {
        let violations = [
            ".background(.ultraThinMaterial)",                    // the obvious one
            "  .background ( .regularMaterial )",                 // spaced out
            "let m = Material.thinMaterial; _ = m",               // not a modifier at all
            "background(scheme == .dark ? .thickMaterial : .ultraThickMaterial)", // inside a ternary
            "Text(\"x\").background(.ultraThinMaterial)  // fine, honestly",      // trailing comment
            "\t.background(.regularMaterial)",                    // tab-indented continuation
        ]
        for line in violations {
            XCTAssertNotNil(Self.violation(in: line), "missed: \(line)")
        }
    }

    func testTheDetectorDoesNotFireOnProseThatMerelyMentionsThem() {
        let innocent = [
            "/// ⚠️ Never `.ultraThinMaterial` / `.regularMaterial` / `.thinMaterial`.",
            "// the legacy build is .ultraThinMaterial throughout",
            "    /// material, never meaning or layout",
            "let materials = 3",
            "static let banned = [\"placeholder\"]",
        ]
        for line in innocent {
            XCTAssertNil(Self.violation(in: line), "false positive: \(line)")
        }
    }

    // MARK: Detector

    /// Looks for the banned token **anywhere** in the code part of the line — not with `hasPrefix`,
    /// which misses everything inline, indented, ternary or trailing.
    static func violation(in line: String) -> String? {
        let code = stripping(comments: line)
        guard !code.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return banned.first { code.contains($0) }
    }

    /// Drops `//` comments, including doc comments, but leaves string literals alone — a banned
    /// token inside a real string is still code that could be rendered.
    static func stripping(comments line: String) -> String {
        var inString = false
        var previous: Character?
        var index = line.startIndex

        while index < line.endIndex {
            let character = line[index]
            if character == "\"" && previous != "\\" { inString.toggle() }
            if !inString, character == "/", previous == "/" {
                return String(line[line.startIndex..<line.index(before: index)])
            }
            previous = character
            index = line.index(after: index)
        }
        return line
    }

    // MARK: Locating the sources

    /// The tests live beside the app, so the repository is found from this file rather than from a
    /// bundle resource — the sources are not copied into the test bundle, and a path built from
    /// `Bundle.main` would point into DerivedData.
    static var appSourceRoot: URL {
        URL(fileURLWithPath: #filePath)          // …/studioUnitTests/MaterialsChecks.swift
            .deletingLastPathComponent()         // …/studioUnitTests
            .deletingLastPathComponent()         // …/aisixteen.studio
            .appendingPathComponent("Studio", isDirectory: true)
    }

    static func swiftFiles(in root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root,
                                                              includingPropertiesForKeys: nil)
        else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}
