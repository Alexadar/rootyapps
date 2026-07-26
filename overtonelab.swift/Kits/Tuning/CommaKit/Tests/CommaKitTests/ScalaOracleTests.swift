import Testing
import Foundation
@testable import CommaKit

/// ORACLE (downloaded fixture): the Scala scale archive — thousands of independently-authored
/// reference tunings. See ../../../tools/oracles.manifest; fetch via tools/fetch-oracles.sh.
/// Fixtures are gitignored; these tests FAIL LOUD if the archive isn't present (never skip green).
@Suite("Scala archive oracle")
struct ScalaOracleTests {

    static var fixturesDir: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    }
    static var sclFiles: [URL] {
        guard let e = FileManager.default.enumerator(at: fixturesDir, includingPropertiesForKeys: nil) else { return [] }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "scl" }
    }
    static func read(_ u: URL) -> String? {
        (try? String(contentsOf: u, encoding: .utf8)) ?? (try? String(contentsOf: u, encoding: .isoLatin1))
    }

    @Test func fixturePresentOrFailLoud() {
        let n = Self.sclFiles.count
        #expect(n >= 100, "Scala archive not downloaded (\(n) .scl found). Run `tools/fetch-oracles.sh`.")
    }

    @Test func parserReadsRealCorpus() throws {
        let files = Self.sclFiles
        try #require(files.count >= 100, "fixtures missing — run tools/fetch-oracles.sh")
        var parsed = 0, monotonic = 0
        for f in files {
            guard let text = Self.read(f), let cents = Tuning.parseSCL(text), !cents.isEmpty else { continue }
            parsed += 1
            if zip(cents, cents.dropFirst()).allSatisfy({ $0.1 > $0.0 }) { monotonic += 1 }
        }
        #expect(parsed > 500, "only \(parsed) scales parsed from \(files.count) files")
        #expect(Double(monotonic) / Double(max(parsed, 1)) > 0.9,
                "monotonic fraction \(Double(monotonic) / Double(max(parsed, 1)))")
    }

    /// Class-A cross-check: the archive's independent quarter-comma meantone entry must carry
    /// the 696.578¢ tempered fifth that our math computes.
    @Test func quarterCommaMeantoneCrossCheck() throws {
        let files = Self.sclFiles
        try #require(files.count >= 100)
        guard let f = files.first(where: { $0.lastPathComponent.lowercased().contains("meanquar") }),
              let cents = Tuning.parseSCL(Self.read(f) ?? "") else {
            Issue.record("meanquar.scl not found — corpus invariant still validates the parser")
            return
        }
        #expect(cents.contains { abs($0 - Tuning.quarterCommaMeantoneFifthCents) < 0.02 },
                "meanquar.scl should contain the 696.578¢ meantone fifth")
    }
}
