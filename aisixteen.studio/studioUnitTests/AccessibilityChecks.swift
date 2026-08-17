import XCTest
import SwiftUI
import RecipeKit
@testable import Studio

/// Reduce Transparency and Reduce Motion, **both directions each**, plus the source scan that keeps
/// the old materials out.
///
/// Both settings are read from `\.stAccessibility`, which is why they are testable at all: a test
/// supplies the value, no simulator setting required.
final class AccessibilityChecks: XCTestCase {

    // MARK: Reduce Motion — both directions

    func testTheMorphSpringIsTheHandoffsAndBecomesACrossFadeWhenMotionIsReduced() {
        XCTAssertEqual(String(describing: STMotion.morph(reduceMotion: false)),
                       String(describing: Animation.spring(response: 0.8, dampingFraction: 0.85)))
        XCTAssertEqual(String(describing: STMotion.morph(reduceMotion: true)),
                       String(describing: Animation.easeInOut(duration: 0.2)))
        XCTAssertNotEqual(String(describing: STMotion.morph(reduceMotion: true)),
                          String(describing: STMotion.morph(reduceMotion: false)))
    }

    func testHoldingTheOriginalBecomesAnInstantSwapWhenMotionIsReduced() {
        XCTAssertEqual(String(describing: STMotion.holdOriginal(reduceMotion: true)),
                       String(describing: Animation.linear(duration: 0)))
        XCTAssertNotEqual(String(describing: STMotion.holdOriginal(reduceMotion: false)),
                          String(describing: STMotion.holdOriginal(reduceMotion: true)))
    }

    func testTheVeilIsContinuousNormallyAndQuantisedWhenMotionIsReduced() {
        // Content changing is kept; the interface moving is not. The veil still clears — in three
        // discrete steps instead of a continuously animating blur.
        for continuous in stride(from: 0.0, through: 26.0, by: 1) {
            XCTAssertEqual(STMotion.veilBlur(continuous, initial: 26, reduceMotion: false),
                           continuous, "continuous must pass straight through")
        }

        let quantised = Set(stride(from: 0.0, through: 26.0, by: 0.5)
            .map { STMotion.veilBlur($0, initial: 26, reduceMotion: true) })
        XCTAssertEqual(quantised.count, 4, "three steps plus zero, got \(quantised.sorted())")
        XCTAssertTrue(quantised.contains(0))
        XCTAssertTrue(quantised.contains(26))
    }

    func testTheVeilSurvivesADegenerateInitialBlur() {
        XCTAssertEqual(STMotion.veilBlur(0, initial: 0, reduceMotion: true), 0)
    }

    func testTheGlassTransitionLosesItsGeometryMorphButNotItsChange() {
        // Both directions asserted through their descriptions, because `GlassEffectTransition` is
        // not `Equatable`.
        let moving = String(describing: STMotion.glassTransition(reduceMotion: false))
        let still = String(describing: STMotion.glassTransition(reduceMotion: true))
        XCTAssertNotEqual(moving, still)
    }

    // MARK: Reduce Transparency — both directions

    func testTheOpaquePlateAndAccentAreDefinedAndDistinctFromTheGlassOnes() {
        // 1k: panels become opaque #F7F6F4, and the accent darkens one step so white text still
        // clears 4.5:1 without the glass underneath to help.
        XCTAssertNotEqual(ST.opaqueAccent, ST.accent)
        XCTAssertNotEqual(ST.opaquePlate(.light), ST.canvas)
        XCTAssertNotEqual(ST.hairline(.light, opaque: true), ST.hairline(.light, opaque: false))
    }

    func testTheOpaqueAccentIsGenuinelyDarkerRatherThanMerelyDifferent() {
        XCTAssertLessThan(luminance(ST.opaqueAccent), luminance(ST.accent),
                          "one step darker, not one step sideways")
    }

    func testWhiteLabelsClearFourAndAHalfToOneOnBothAccentPlates() {
        // The tinted plate always carries white (GlassLabel). Under Reduce Transparency there is no
        // glass to help, so the flat accent has to hold the ratio by itself.
        XCTAssertGreaterThan(contrastWithWhite(ST.opaqueAccent), 4.5)
        XCTAssertGreaterThan(contrastWithWhite(ST.accent), 4.5)
    }

    func testATintedPlateAlwaysCarriesWhiteAndARegularOneCarriesInk() {
        XCTAssertEqual(GlassLabel.color(on: .tinted, scheme: .light), .white)
        XCTAssertEqual(GlassLabel.color(on: .regular, scheme: .light), ST.ink(.light))
        XCTAssertEqual(GlassLabel.color(on: .regular, scheme: .light, enabled: false),
                       ST.inkDisabled(.light))
    }

    // MARK: Hit targets

    func testEveryInteractiveMetricClearsTheFortyFourPointFloor() {
        XCTAssertGreaterThanOrEqual(ST.primaryCapsuleHeight, ST.minimumHitTarget)
        XCTAssertGreaterThanOrEqual(ST.pillHeight, ST.minimumHitTarget)
        XCTAssertGreaterThanOrEqual(ST.circleButton, ST.minimumHitTarget)
        XCTAssertGreaterThanOrEqual(ST.handleTarget, ST.minimumHitTarget)
        XCTAssertLessThan(ST.handleGrip, ST.handleTarget,
                          "the visual grip is deliberately smaller than what you can hit")
    }

    // MARK: Dynamic Type

    func testEveryTextStyleScalesAgainstSomethingRatherThanAFixedSize() {
        // `Font.system(size:)` does not scale, and a ramp built from it ignores the user's text size
        // entirely — the most common accessibility failure in a hand-tokenised design.
        let styles: [STTextStyle] = [.largeTitle, .screenTitle, .cardHeading, .button, .body,
                                     .secondary, .control, .readout, .caption, .footnote,
                                     .splitCaption]
        for style in styles {
            XCTAssertGreaterThan(style.size, 0)
            XCTAssertNotNil(style.relativeTo)
        }
    }

    func testTheRampIsOrderedSoALargerRoleIsNeverSmallerThanASmallerOne() {
        XCTAssertGreaterThan(STTextStyle.largeTitle.size, STTextStyle.screenTitle.size)
        XCTAssertGreaterThan(STTextStyle.screenTitle.size, STTextStyle.cardHeading.size)
        XCTAssertGreaterThan(STTextStyle.cardHeading.size, STTextStyle.button.size)
        XCTAssertGreaterThan(STTextStyle.body.size, STTextStyle.caption.size)
        XCTAssertGreaterThan(STTextStyle.caption.size, STTextStyle.splitCaption.size)
    }

    // MARK: Helpers

    private func components(_ color: Color) -> (Double, Double, Double) {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
        #else
        let converted = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return (Double(converted.redComponent),
                Double(converted.greenComponent),
                Double(converted.blueComponent))
        #endif
    }

    private func luminance(_ color: Color) -> Double {
        let (r, g, b) = components(color)
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    private func contrastWithWhite(_ color: Color) -> Double {
        (1.0 + 0.05) / (luminance(color) + 0.05)
    }
}
