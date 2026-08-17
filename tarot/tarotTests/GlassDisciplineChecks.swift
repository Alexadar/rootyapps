import XCTest
@testable import Tarot

/// Source-scanning discipline for the chrome (the aisixteen pattern):
///  * `.glassEffect` lives in GlassTreatments.swift and NOWHERE else — one bare call site
///    elsewhere ships a screen that ignores Reduce Transparency;
///  * the previous-generation materials are banned everywhere;
///  * the trademarked deck brand appears in no source file;
///  * and the scanners are proven to fire (a guard that never fires proves nothing).
final class GlassDisciplineChecks: XCTestCase {

    static var appSources: [(name: String, text: String)] = {
        // …/tarot/tarotTests/GlassDisciplineChecks.swift → …/tarot/Tarot
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tarot")
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { return [] }
        var out: [(String, String)] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                out.append((url.lastPathComponent, text))
            }
        }
        return out.sorted { $0.0 < $1.0 }
    }()

    func testAppSourcesAreDiscoverable() {
        // If the walk breaks, every scan below passes vacuously and proves nothing.
        XCTAssertGreaterThanOrEqual(Self.appSources.count, 10,
                                    "found only \(Self.appSources.map(\.name))")
        XCTAssertTrue(Self.appSources.contains { $0.name == "GlassTreatments.swift" })
    }

    func testGlassEffectOnlyInTreatments() {
        for (name, text) in Self.appSources where name != "GlassTreatments.swift" {
            XCTAssertFalse(text.contains(".glassEffect"),
                           "bare .glassEffect outside GlassTreatments.swift, in \(name)")
        }
        let treatments = Self.appSources.first { $0.name == "GlassTreatments.swift" }?.text ?? ""
        XCTAssertTrue(treatments.contains(".glassEffect") || treatments.contains("glassEffect("),
                      "GlassTreatments.swift no longer calls glassEffect — the discipline test has gone vacuous")
    }

    func testPreviousGenerationMaterialsAreBanned() {
        for (name, text) in Self.appSources {
            for banned in [".ultraThinMaterial", ".regularMaterial", ".thinMaterial",
                           ".thickMaterial", ".ultraThickMaterial"] {
                XCTAssertFalse(text.contains(banned), "\(name) uses previous-generation \(banned)")
            }
        }
    }

    /// "Rider-Waite" is a live trademark; the deck is described as "the classic 1909 deck".
    /// The ban covers every source file — strings, comments, identifiers.
    func testTrademarkedBrandAppearsNowhere() {
        for (name, text) in Self.appSources {
            XCTAssertFalse(text.lowercased().contains("rider"),
                           "trademarked brand fragment in \(name)")
        }
    }

    /// Cards are lit 3D objects; glass is chrome. The renderer must not import SwiftUI, and
    /// the treatments file must not leak into the Render layer.
    func testNoGlassInTheRenderLayer() {
        for (name, text) in Self.appSources
        where ["RealityCardRenderer.swift", "CardRenderer.swift", "Shaders.metal"].contains(name) {
            XCTAssertFalse(text.contains("glassEffect"), "\(name) puts glass on the cards")
        }
    }

    // Negative checks: the scanners fire on the violations they exist to catch.
    func testTheScannersActuallyFire() {
        let violation = "struct Bad: View { var body: some View { Text(\"x\").glassEffect() } }"
        XCTAssertTrue(violation.contains(".glassEffect"))
        let material = "  .background(.ultraThinMaterial)"
        XCTAssertTrue(material.contains(".ultraThinMaterial"))
        let brand = "// based on the Rider deck"
        XCTAssertTrue(brand.lowercased().contains("rider"))
    }
}
