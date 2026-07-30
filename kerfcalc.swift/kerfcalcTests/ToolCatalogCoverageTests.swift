import Testing
import Foundation
@testable import KerfCalc

/// Catalog-level guards, and the keypad identifier table.
///
/// `CalculationChecks.testEveryToolHasANumericCheck` in the UI suite asserts its coverage list has 20
/// entries, but a UI-test bundle does not link the app module, so it cannot compare that against
/// `Tool.allCases.count`. This does, from inside the app target. The two together mean a twenty-first
/// calculator fails a test whichever side it is added from.
@Suite struct ToolCatalogCoverageTests {

    /// The number the UI suite's coverage list is pinned to.
    private let coveredByUISuite = 20

    @Test func theCatalogShipsTheNumberOfToolsTheUISuiteCovers() {
        #expect(Tool.allCases.count == coveredByUISuite,
                "the catalog has \(Tool.allCases.count) tools but CalculationChecks covers \(coveredByUISuite) — update both")
    }

    /// Raw values are the deep-link vocabulary (`KERFCALC_TOOL`) and the favourites storage keys, so a
    /// duplicate would silently alias two tools to one screen and one favourite.
    @Test func everyToolHasAUniqueRawValue() {
        let raws = Tool.allCases.map(\.rawValue)
        #expect(Set(raws).count == raws.count, "duplicate Tool rawValue in \(raws)")
    }

    /// Every tool is reachable from exactly one section, and the sections partition the catalog. A tool
    /// in no section is unreachable from the grid; one in two sections appears twice.
    @Test func sectionsPartitionTheCatalog() {
        let grouped = ToolSection.allCases.flatMap { Tool.tools(in: $0) }
        #expect(grouped.count == Tool.allCases.count, "sections do not partition the catalog")
        #expect(Set(grouped) == Set(Tool.allCases))
    }

    /// The app's central claim is that every number has a source, so no tool may ship without its
    /// formula and citation.
    @Test func everyToolCitesAFormula() {
        for t in Tool.allCases {
            #expect(!t.formula.isEmpty, "\(t.rawValue) has no formula")
            #expect(!t.citation.isEmpty, "\(t.rawValue) has no citation")
            #expect(!t.title.isEmpty, "\(t.rawValue) has no title")
        }
    }

    /// Deep links round-trip: every raw value the UI suite passes in `KERFCALC_TOOL` must parse back.
    @Test func everyToolRawValueParsesBack() {
        for t in Tool.allCases { #expect(Tool(rawValue: t.rawValue) == t) }
    }

    /// **The watch must carry every phone calculator.**
    ///
    /// The watch app shipped 6 of these 20 for a while — it built, ran, and passed its own suite the
    /// whole time, because nothing asserted the wrist catalog was *complete*. `WatchToolList` is driven
    /// by `Tool.tools(in:)`, so the list itself cannot drift; what can drift is
    /// `WatchRootView.screen(for:)`, and this is the counterpart to the compile-time guarantee there
    /// (that switch has no `default:`, so a missing screen fails to build).
    ///
    /// Kept in the app target because `Tool.allCases` is not reachable from a UI-test bundle;
    /// `KerfCalcWatchUITests/WatchCalculationChecks.testEveryWatchToolHasANumericCheck` pins the same
    /// number from the other side.
    @Test func watchCoversEveryPhoneTool() {
        #expect(Tool.allCases.count == 20,
                "the watch's coverage lists are written against 20 tools — update them together")
        // Every section the watch list renders must be non-empty, or a trade header shows with no rows.
        for s in ToolSection.allCases {
            #expect(!Tool.tools(in: s).isEmpty, "section \(s.rawValue) would render an empty header")
        }
    }

    // MARK: - Keypad identifiers

    /// The Spec pad's test handles are derived from `SpecKeypad.KeyID`, so they cannot drift from the
    /// model — but they CAN be renamed, and that would turn every keypad test into a "missing element"
    /// failure at once, which reads like the keypad never rendered. Pin the table.
    @Test func specKeypadIdentifiersAreStable() {
        #expect(SpecKeypad.name(.digit(0)) == "digit0")
        #expect(SpecKeypad.name(.digit(9)) == "digit9")
        #expect(SpecKeypad.name(.feet) == "feet")
        #expect(SpecKeypad.name(.inch) == "inch")
        #expect(SpecKeypad.name(.frac) == "fraction")
        #expect(SpecKeypad.name(.add) == "op.add")
        #expect(SpecKeypad.name(.sub) == "op.sub")
        #expect(SpecKeypad.name(.mul) == "op.mul")
        #expect(SpecKeypad.name(.div) == "op.div")
        #expect(SpecKeypad.name(.equals) == "equals")
        #expect(SpecKeypad.name(.clear) == "clear")
        #expect(SpecKeypad.name(.backspace) == "backspace")
    }

    /// Every key id must be unique, or two keys collide and a test taps whichever comes first.
    @Test func specKeypadIdentifiersAreUnique() {
        let ids: [SpecKeypad.KeyID] = [.feet, .inch, .frac, .backspace,
                                       .rise, .run, .diag, .pitch,
                                       .rafter, .stair, .area, .vol,
                                       .div, .mul, .sub, .add, .clear, .equals]
            + (0...9).map { SpecKeypad.KeyID.digit($0) }
        let names = ids.map(SpecKeypad.name)
        #expect(Set(names).count == names.count, "duplicate keypad identifier in \(names)")
    }
}
