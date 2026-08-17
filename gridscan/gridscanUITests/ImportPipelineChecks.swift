import XCTest

/// The one true end-to-end test: a REAL born-digital PDF through the REAL import
/// pipeline (decider → text layer → TableStructureKit → store) via the DEBUG
/// GRIDSCAN_IMPORT hook. Camera capture cannot run in the simulator and is excluded.
final class ImportPipelineChecks: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testBornDigitalPDFImportsAsATable() throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: "table", withExtension: "pdf"),
                                    "fixture PDF missing from the test bundle")
        // Fresh store, NO fixtures — only the import result should exist.
        let app = XCUIApplication()
        app.launchEnvironment["GRIDSCAN_STORE"] = "memory"
        app.launchEnvironment["GRIDSCAN_IMPORT"] = fixture.path
        app.launch()

        // The imported document appears in the Library with its as-read title...
        XCTAssertTrue(app.descendants(matching: .any)
            .containing(textMatches("Field observations")).firstMatch
            .waitForExistence(timeout: 30), "imported document tile did not appear")

        // ...and the audit trail records the per-page source decision.
        app.descendants(matching: .any).containing(textMatches("Activity"))
            .firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)
            .containing(textMatches("text layer")).firstMatch.waitForExistence(timeout: 10),
                      "page-source line missing from the imported audit event")
        app.terminate()
    }

    func testImportedTableOpensWithExtractedCells() throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: "table", withExtension: "pdf"))
        let app = XCUIApplication()
        app.launchEnvironment["GRIDSCAN_STORE"] = "memory"
        app.launchEnvironment["GRIDSCAN_IMPORT"] = fixture.path
        app.launchEnvironment["GRIDSCAN_DOC"] = "Field observations"
        app.launch()

        XCTAssertTrue(any(app, "grid.cell.0.0").waitForExistence(timeout: 30))
        // Ground truth from tools/make_fixture_pdf.swift.
        for value in ["Plot", "Species", "Count", "willow warbler", "sedge warbler", "7"] {
            XCTAssertTrue(app.descendants(matching: .any)
                .containing(textMatches(value)).firstMatch.exists,
                          "extracted value missing: \(value)")
        }
        app.terminate()
    }
}
