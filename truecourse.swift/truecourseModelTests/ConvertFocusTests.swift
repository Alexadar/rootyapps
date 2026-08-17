import XCTest
@testable import TrueCourse

/// Regression guard for the watch Convert crown-focus steal: scrolling the category/unit picker (or
/// the value) must NOT move the crown to another control — only a tap does. The old code called
/// `reclaim()` in the pickers' `.onChange`, firing on every crown tick and yanking focus back to the
/// value field after one step. `ConvertFocus` is the extracted policy the watch view mirrors into
/// `@FocusState`; watchOS has no XCUITest, so this pure model is where the rule is proven.
@MainActor
final class ConvertFocusTests: XCTestCase {

    /// The core regression: after focusing a control, every crown-driven mutation leaves focus put.
    func testCrownDrivenChangesNeverMoveFocus() {
        let m = ConvertFocus()
        m.focus(.category)
        XCTAssertEqual(m.field, .category)

        m.setValue(42)
        XCTAssertEqual(m.field, .category, "changing the value must not move focus")
        m.setUnit(1)
        XCTAssertEqual(m.field, .category, "changing the unit must not move focus")
        m.setCategory(3)
        XCTAssertEqual(m.field, .category, "changing the category must not move focus")
    }

    /// Scrolling a picker across many ticks (the exact wrist gesture) keeps its focus the whole way.
    func testManyScrollTicksKeepFocus() {
        let m = ConvertFocus()
        m.focus(.value)
        for v in stride(from: 0.0, through: 60, by: 1) { m.setValue(v) }
        XCTAssertEqual(m.field, .value)
        XCTAssertEqual(m.value, 60)
    }

    /// A tap is the only thing that switches the crown target.
    func testTapSwitchesFocus() {
        let m = ConvertFocus()
        XCTAssertEqual(m.field, .value)             // default target
        m.focus(.category); XCTAssertEqual(m.field, .category)
        m.focus(.unit);     XCTAssertEqual(m.field, .unit)
        m.focus(.value);    XCTAssertEqual(m.field, .value)
    }

    /// Switching category resets the unit (new category, different unit set) — but keeps focus.
    func testSetCategoryResetsUnitButKeepsFocus() {
        let m = ConvertFocus()
        m.focus(.unit)
        m.setUnit(2)
        m.setCategory(1)
        XCTAssertEqual(m.unitIdx, 0, "a new category resets the from-unit")
        XCTAssertEqual(m.field, .unit, "focus stays where the user put it")
    }

    /// Re-selecting the SAME category is a no-op — it must not stomp the unit the user just chose.
    func testSetCategoryNoOpWhenUnchanged() {
        let m = ConvertFocus()
        m.setUnit(2)
        m.setCategory(0)                            // already 0
        XCTAssertEqual(m.unitIdx, 2)
    }
}
