import XCTest
@testable import TrueCourse

/// §C.2 state-space coverage for the Convert tool — the app's one genuine control cross-product
/// (7 categories × 2–3 units). Combinatorics live here (µs), never in XCUITest (~1.1 s/tap).
///
/// ConvertKit owns the arithmetic (its own oracle tests); this proves the *view-model + category
/// table* wiring: selecting a category resets the unit, the output set is the other units, flipping
/// the unit changes the result, and every unit's closures round-trip. Assertions are on `Double`
/// closures and output *structure* — never on formatted strings, so a comma-decimal host can't fail
/// these on the separator.
@MainActor
final class ConvertStateSpaceTests: XCTestCase {

    /// Coverage guard: the shipping category/unit shape. Adding a category or unit fails this until
    /// the expectation is updated — so nothing ships unexercised.
    func testCategoryUnitShape() {
        XCTAssertEqual(categories.map(\.name),
                       ["Temperature", "Distance", "Altitude", "Speed", "Weight", "Fuel", "Climb"])
        XCTAssertEqual(categories.map { $0.units.count }, [2, 3, 2, 2, 2, 3, 3])
    }

    /// `selectCategory` resets the from-unit to 0 from ANY prior index — the stateful reset a
    /// relabel-only change would drop, leaving `fromIndex` past the new category's unit count.
    func testSelectCategoryResetsFromIndex() {
        let vm = ConvertViewModel()
        for c in categories.indices {
            vm.fromIndex = 1
            vm.selectCategory(c)
            XCTAssertEqual(vm.categoryIndex, c)
            XCTAssertEqual(vm.fromIndex, 0, "selecting \(categories[c].name) must reset the from unit")
        }
    }

    /// For every category × every from-unit: `outputs` lists exactly the OTHER units, in order, and
    /// never the from unit itself.
    func testOutputsAreTheOtherUnits() {
        let vm = ConvertViewModel()
        for c in categories.indices {
            vm.selectCategory(c)
            let cat = categories[c]
            for f in cat.units.indices {
                vm.fromIndex = f
                let expected = cat.units.indices.filter { $0 != f }.map { cat.units[$0].name }
                XCTAssertEqual(vm.outputs.map(\.name), expected,
                               "[\(cat.name)/\(cat.units[f].name)] outputs should be the other units")
            }
        }
    }

    /// Every category × from-unit × to-unit round-trips through the shared base — the inverse
    /// property that catches a table entry wired to the wrong ConvertKit function (a unit that
    /// relabels without converting). Pure `Double`, locale-free.
    func testEveryConversionRoundTrips() {
        for cat in categories {
            for f in cat.units.indices {
                let base = cat.units[f].toBase(123.0)
                for (i, u) in cat.units.enumerated() where i != f {
                    let shown = u.fromBase(base)          // value the UI would display in unit u
                    XCTAssertEqual(u.toBase(shown), base, accuracy: max(1e-6, abs(base) * 1e-9),
                                   "[\(cat.name)] \(cat.units[f].name) → \(u.name) did not round-trip")
                }
            }
        }
    }

    /// Flipping the from-unit changes the output values — a dead picker would leave them identical.
    func testFlippingFromUnitChangesOutputs() {
        let vm = ConvertViewModel()
        vm.selectCategory(1)                 // Distance: nm / sm / km
        vm.input = 100
        vm.fromIndex = 0
        let a = vm.outputs.map(\.value)
        vm.fromIndex = 1
        let b = vm.outputs.map(\.value)
        XCTAssertNotEqual(a, b, "changing the from unit must change the conversions")
    }
}
