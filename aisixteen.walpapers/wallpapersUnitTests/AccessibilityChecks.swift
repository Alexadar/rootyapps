import XCTest
import SwiftUI
@testable import Wallpapers

/// Reduce Motion and Reduce Transparency, **both directions**.
///
/// The house rule exists because a toggle that is only ever seen in its default state ships dead. In
/// a glass-heavy design these two are the settings most likely to be written once and never
/// exercised, and the property that matters is not "something changed" but "the material changed and
/// the geometry did not" — a Reduce Transparency pass that also moves things has changed meaning,
/// which is precisely what the setting must not do.
final class AccessibilityChecks: XCTestCase {

    // MARK: Reduce Motion

    func testTheMorphSpringIsTheBundlesAndBecomesACrossfade() {
        let springing = WPMotion.morph(reduceMotion: false)
        let crossfading = WPMotion.morph(reduceMotion: true)
        XCTAssertNotEqual(springing, crossfading, "Reduce Motion changed nothing")
        XCTAssertEqual(springing, .spring(response: 0.8, dampingFraction: 0.85))
        XCTAssertEqual(crossfading, .easeInOut(duration: 0.2))
    }

    func testTheFinalRevealAlsoRespectsReduceMotion() {
        XCTAssertEqual(WPMotion.reveal(reduceMotion: false), .spring(response: 0.5, dampingFraction: 0.85))
        XCTAssertEqual(WPMotion.reveal(reduceMotion: true), .easeInOut(duration: 0.2))
    }

    func testTheProgressFillNeverSprings() {
        // A bar that overshoots is reporting a step the run has not reached — true in both modes.
        XCTAssertEqual(WPMotion.progressFill, .linear(duration: 0.25))
    }

    func testTheVeilIsContinuousNormallyAndSteppedUnderReduceMotion() {
        let samples = stride(from: 26.0, through: 0.0, by: -1.0)

        let continuous = samples.map { WPMotion.veilBlur($0, initial: 26, reduceMotion: false) }
        XCTAssertEqual(Set(continuous).count, continuous.count,
                       "the normal veil should be continuous, not quantised")

        let stepped = samples.map { WPMotion.veilBlur($0, initial: 26, reduceMotion: true) }
        XCTAssertEqual(Set(stepped).count, 4,
                       "Reduce Motion should give three visible steps plus zero, got \(Set(stepped).sorted())")
    }

    func testTheVeilStillReachesZeroInBothModes() {
        // Kept, not removed: the emerging picture is content changing, not the interface moving.
        XCTAssertEqual(WPMotion.veilBlur(0, initial: 26, reduceMotion: true), 0)
        XCTAssertEqual(WPMotion.veilBlur(0, initial: 26, reduceMotion: false), 0)
        XCTAssertEqual(WPMotion.veilBlur(26, initial: 26, reduceMotion: true), 26)
    }

    func testTheVeilNeverGoesBackwardsUnderReduceMotion() {
        var previous = Double.infinity
        for step in stride(from: 26.0, through: 0.0, by: -0.5) {
            let value = WPMotion.veilBlur(step, initial: 26, reduceMotion: true)
            XCTAssertLessThanOrEqual(value, previous + 1e-9, "the stepped veil thickened at \(step)")
            previous = value
        }
    }

    // MARK: Reduce Transparency

    func testTheOpaqueSubstitutesAreTheBundlesTokens() {
        // #F2F0EB light, #2C2E38 dark — stated in `1h`, and the only two values allowed here.
        XCTAssertEqual(WP.opaquePlate(.light), Color(hex: 0xF2F0EB))
        XCTAssertEqual(WP.opaquePlate(.dark), Color(hex: 0x2C2E38))
    }

    func testTheOpaqueTintIsDarkenedSoWhiteTextStillHolds() {
        // Without glass underneath, the 75 % accent would not carry white at 4.5:1.
        XCTAssertEqual(WP.opaqueAccent, Color(hex: 0x0A6FD6))
        XCTAssertNotEqual(WP.opaqueAccent, WP.accent)
    }

    func testTheHairlineSurvivesWhenTheMaterialDoesNot() {
        // The plate's edge is what separates it from the backdrop once the blur is gone.
        for scheme in [ColorScheme.light, .dark] {
            XCTAssertNotEqual(WP.hairline(scheme, opaque: true), Color.clear)
            XCTAssertNotEqual(WP.hairline(scheme, opaque: true), WP.hairline(scheme, opaque: false),
                              "an opaque plate needs a different edge from a glass one")
        }
    }

    // MARK: Legibility

    func testATintedPlateAlwaysCarriesWhiteAndARegularOneCarriesInk() {
        XCTAssertEqual(GlassLabel.color(on: .tinted, scheme: .light), .white)
        XCTAssertEqual(GlassLabel.color(on: .tinted, scheme: .dark), .white)
        XCTAssertEqual(GlassLabel.color(on: .regular, scheme: .light), WP.ink(.light))
        XCTAssertEqual(GlassLabel.color(on: .regular, scheme: .dark), WP.ink(.dark))
    }

    func testDisabledReadsByWeightAndOpacityRatherThanByColourAlone() {
        let enabled = GlassLabel.color(on: .regular, scheme: .light, enabled: true)
        let disabled = GlassLabel.color(on: .regular, scheme: .light, enabled: false)
        XCTAssertNotEqual(enabled, disabled)
        XCTAssertEqual(disabled, WP.inkDisabled(.light))
    }

    func testInkHasThreeDistinctWeightsInBothThemes() {
        for scheme in [ColorScheme.light, .dark] {
            let weights = [WP.ink(scheme), WP.ink2(scheme), WP.ink3(scheme)]
            XCTAssertEqual(Set(weights).count, 3, "ink weights collapsed in \(scheme)")
        }
    }

    func testSuccessAndDestructiveDifferBetweenThemes() {
        // The bundle gives each two values because the light-theme pair would not hold on a dark
        // plate, and vice versa.
        XCTAssertNotEqual(WP.success(.light), WP.success(.dark))
        XCTAssertNotEqual(WP.destructive(.light), WP.destructive(.dark))
    }

    // MARK: Geometry

    func testTheRadiusLadderIsConcentricAndOrdered() {
        let ladder = [WP.Radius.screen, WP.Radius.sheet, WP.Radius.frame, WP.Radius.card,
                      WP.Radius.plate, WP.Radius.tile]
        XCTAssertEqual(ladder, ladder.sorted(by: >), "radii must decrease from screen inward")
    }

    func testEveryInteractiveSizeClearsTheHitTargetFloor() {
        // `circleButton` (56) was here and is gone: no view ever rendered it, so this loop was
        // asserting a floor on a size nothing could violate. A test over a value with no call site
        // is a green check on dead weight — it makes the ladder look verified while covering one
        // rung fewer than it names.
        for size in [WP.primaryCapsuleHeight, WP.pillHeight, WP.smallCircleButton] {
            XCTAssertGreaterThanOrEqual(size, WP.minimumHitTarget, "\(size) is below 44 pt")
        }
    }
}
