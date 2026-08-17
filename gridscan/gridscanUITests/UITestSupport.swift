import XCTest

// Cross-platform primitives (uitests.md §3): query by IDENTIFIER, never by element
// type; on macOS a plain Text has an EMPTY label (its string is in value), so all
// text checks go through `text`/`textMatches`.

extension XCUIElement {
    var text: String {
        let l = label
        if !l.isEmpty { return l }
        return (value as? String) ?? ""
    }
}

func textMatches(_ needle: String) -> NSPredicate {
    NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", needle, needle)
}

func any(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
}

/// Launch with the standard deterministic setup: REAL SwiftData store in an ephemeral
/// in-memory container, seeded with the fixture catalog. Extra env merges on top.
func launchGridScan(_ extra: [String: String] = [:]) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["GRIDSCAN_STORE"] = "memory"
    app.launchEnvironment["GRIDSCAN_FIXTURES"] = "1"
    for (k, v) in extra { app.launchEnvironment[k] = v }
    app.launch()
    return app
}

/// The six fixture titles (FixtureCatalog.standard), used across checks.
enum Fixture {
    static let soil = "Soil sample log — Plot 7 spring survey"
    static let race = "Race results — 200 m freestyle heats"
    static let roster = "Vaccination roster — Ward B"
    static let weather = "Daily observations — Station Kestrel"
    static let checklist = "Maintenance checklist — press no. 3"
    static let register = "Accession register — March additions"
    static let all = [soil, race, roster, weather, checklist, register]
}
