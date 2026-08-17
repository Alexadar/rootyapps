import XCTest
@testable import RecipeKit

/// The dial, at every value the design names and at both ends of the rail.
final class StrengthTests: XCTestCase {

    func testTheFourDetentsAreTheHandoffsNumbers() {
        XCTAssertEqual(Detent.whisper.rawValue, 15)
        XCTAssertEqual(Detent.subtle.rawValue, 35)
        XCTAssertEqual(Detent.balanced.rawValue, 55)
        XCTAssertEqual(Detent.strong.rawValue, 80)
        XCTAssertEqual(Detent.allCases.count, 4)
    }

    func testTheDefaultIsSubtleAndNotSomethingLouder() {
        // Conservative on purpose: the category's top complaint is "it doesn't look like my photo".
        XCTAssertEqual(Detent.default, .subtle)
        XCTAssertEqual(Strength.default, Strength(35))
    }

    func testTheRailClampsInsteadOfTrapping() {
        XCTAssertEqual(Strength(-40).value, 0)
        XCTAssertEqual(Strength(140).value, 100)
        XCTAssertEqual(Strength(.nan).value, 0)
        XCTAssertEqual(Strength(.infinity).value, 100)
    }

    func testEveryDetentPlusBothEndsOfTheRail() {
        let cases: [(Strength, String?)] = [
            (.zero, nil),
            (.whisper, "Whisper"),
            (.subtle, "Subtle"),
            (.balanced, "Balanced"),
            (.strong, "Strong"),
            (.full, nil),
        ]
        for (strength, name) in cases {
            XCTAssertEqual(strength.detent?.name, name, "at \(strength.value)")
        }
    }

    func testVoiceOverGetsNamesNotBareNumbers() {
        // 1j is explicit: the slider announces detent names.
        XCTAssertEqual(Strength.subtle.accessibilityValue, "Subtle")
        XCTAssertEqual(Strength.balanced.accessibilityValue, "Balanced")
        XCTAssertEqual(Strength.zero.accessibilityValue, "Off. Showing the original.")

        // Between detents there is no name to give, so it must not be a naked figure either — it
        // names the two steps the value sits between.
        XCTAssertEqual(Strength(42).accessibilityValue, "42, between Subtle and Balanced")
        XCTAssertEqual(Strength(8).accessibilityValue, "8, below Whisper")
        XCTAssertEqual(Strength(95).accessibilityValue, "95, above Strong")
    }

    func testOnlyStrongWarns() {
        XCTAssertNil(Strength.whisper.warning)
        XCTAssertNil(Strength.subtle.warning)
        XCTAssertNil(Strength.balanced.warning)
        XCTAssertEqual(Strength.strong.warning, "May alter fine details.")
        XCTAssertNotNil(Strength.full.warning, "above Strong the warning must not disappear")
    }

    func testTheSliderSettlesOntoDetentsButNotOntoDistantOnes() {
        XCTAssertEqual(Strength(36).snapped(), Strength(35))
        XCTAssertEqual(Strength(13).snapped(), Strength(15))
        XCTAssertEqual(Strength(78).snapped(), Strength(80))

        // 45 is between Subtle and Balanced and belongs to neither.
        XCTAssertEqual(Strength(45).snapped(), Strength(45))
        XCTAssertEqual(Strength(20).snapped(), Strength(20))
    }

    func testSnappingPrefersTheNearerDetentWhenTwoAreInRange() {
        // Only reachable with a wide tolerance, but it must still pick the nearer one …
        XCTAssertEqual(Strength(44).snappingDetent(tolerance: 12), .subtle)     // 9 away vs 11
        XCTAssertEqual(Strength(50).snappingDetent(tolerance: 12), .balanced)   // 5 away vs 15

        // … and an exact tie must resolve the same way every time, not by hash order.
        XCTAssertEqual(Strength(45).snappingDetent(tolerance: 12), .subtle)
        XCTAssertEqual(Strength(45).snappingDetent(tolerance: 12),
                       Strength(45).snappingDetent(tolerance: 12))
    }

    func testDisplayNamePairsTheNameWithTheNumber() {
        XCTAssertEqual(Strength.subtle.displayName, "Subtle · 35")
        XCTAssertEqual(Strength.zero.displayName, "Off")
        XCTAssertEqual(Strength(42).displayName, "42")
    }

    func testStrengthRoundTripsThroughJSONAsAPlainNumber() throws {
        let data = try JSONEncoder().encode(Strength.balanced)
        XCTAssertEqual(String(data: data, encoding: .utf8), "55",
                       "a recipe a user can read in Files should not carry a wrapper object")
        XCTAssertEqual(try JSONDecoder().decode(Strength.self, from: data), .balanced)
    }

    func testDecodingAnOutOfRangeStrengthClampsRatherThanThrowing() throws {
        let decoded = try JSONDecoder().decode(Strength.self, from: Data("999".utf8))
        XCTAssertEqual(decoded.value, 100, "a corrupt recipe must open, not crash the library")
    }
}
