import SwiftUI
import XCTest
@testable import Architecture

/// Both accessibility settings, both directions.
///
/// These are unit tests rather than UI tests precisely because `AccessibilityMode` is an injected
/// environment value: a setting you can only reach through Settings is a setting that gets tested
/// once, by hand, and then never again.
@MainActor
final class AccessibilityChecks: XCTestCase {

    // ── Reduce Motion ────────────────────────────────────────────────────────────────────────

    func testReduceMotionReplacesTheMorphWithACrossFade() {
        let spring = ARCMotion.morph(reduceMotion: false)
        let fade = ARCMotion.morph(reduceMotion: true)
        XCTAssertNotEqual(spring, fade)
        XCTAssertEqual(spring, .spring(response: 0.8, dampingFraction: 0.85),
                       "the design bundle's morph spec")
        XCTAssertEqual(fade, .easeInOut(duration: 0.2))
    }

    /// ⚠️ This covers a token that is DECLARED AND NOT WIRED. It asserts the value is distinct
    /// from `morph`, which is true — and says nothing about whether cancelling actually plays it,
    /// because nothing calls it. Do not read this green as "cancel reverses". The tripwire in
    /// `SourceGuardChecks` is what tracks the wiring; this only pins the value.
    func testCancelReverseIsADistinctAnimation_notYetWired() {
        // "Cancel plays the morph in reverse" — stated in the token table, absent from the mockups,
        // which had one animation and no reverse.
        XCTAssertNotEqual(ARCMotion.morph(reduceMotion: false),
                          ARCMotion.cancelReverse(reduceMotion: false))
        XCTAssertNotEqual(ARCMotion.morph(reduceMotion: true),
                          ARCMotion.cancelReverse(reduceMotion: true))
    }

    /// ⚠️ Also a DECLARED AND NOT WIRED token — see the note above.
    func testGlassTransitionDegradesInBothDirections_notYetWired() {
        XCTAssertNotEqual(String(describing: ARCMotion.glassTransition(reduceMotion: false)),
                          String(describing: ARCMotion.glassTransition(reduceMotion: true)))
    }

    func testTheProgressBarNeverSprings() {
        // A bar that overshoots its step count is telling the user something happened that did not.
        XCTAssertEqual(ARCMotion.progressFill, .linear(duration: 0.25))
    }

    func testTheVeilBecomesSteppedStillsUnderReduceMotion() {
        // "Intermediates as stepped stills (no live blur easing)."
        var continuous = Set<CGFloat>()
        var stepped = Set<CGFloat>()
        for step in 0...32 {
            continuous.insert(ARCMotion.veilBlur(atStep: step, totalSteps: 32, reduceMotion: false))
            stepped.insert(ARCMotion.veilBlur(atStep: step, totalSteps: 32, reduceMotion: true))
        }
        XCTAssertGreaterThan(continuous.count, 20, "the normal veil eases continuously")
        XCTAssertLessThanOrEqual(stepped.count, 4, "reduced motion quantises it into stills")
        XCTAssertGreaterThan(stepped.count, 1, "…but it still has to progress")
    }

    func testTheVeilStartsAndEndsWhereTheTokensSay() {
        for reduceMotion in [false, true] {
            XCTAssertEqual(ARCMotion.veilBlur(atStep: 0, totalSteps: 32, reduceMotion: reduceMotion),
                           ARC.Veil.blurStart)
            XCTAssertEqual(ARCMotion.veilBlur(atStep: 32, totalSteps: 32, reduceMotion: reduceMotion),
                           ARC.Veil.blurEnd)
        }
        XCTAssertEqual(ARC.Veil.opacity, 0.22)
        XCTAssertEqual(ARC.Veil.blurStart, 26)
    }

    func testTheVeilNeverGoesBackwards() {
        for reduceMotion in [false, true] {
            var previous = CGFloat.infinity
            for step in 0...32 {
                let blur = ARCMotion.veilBlur(atStep: step, totalSteps: 32, reduceMotion: reduceMotion)
                XCTAssertLessThanOrEqual(blur, previous, "the image only ever gets clearer")
                previous = blur
            }
        }
    }

    // ── Reduce Transparency ──────────────────────────────────────────────────────────────────

    func testTheOpaquePlateTokenExistsAndIsTheOneTheReadmeNames() {
        // Named in the README's accessibility floor and completely absent from the handoff Swift,
        // where nothing responded to the setting at all.
        XCTAssertEqual(ARC.opaquePlate.hexString, "F6F3ED")
    }

    func testTheAccessibilityModeIsInjectable() {
        // This is what makes both settings unit-testable at all.
        // `.reducedTransparency` and `.both` are deliberate TEST FIXTURES — referenced only from
        // tests, by design. The app never reads them: it builds an `AccessibilityMode` from the
        // real environment in `AccessibilityModeReader`. Recorded so a dead-token sweep does not
        // mistake them for something nothing renders.
        XCTAssertEqual(AccessibilityMode.standard, AccessibilityMode(reduceMotion: false, reduceTransparency: false))
        XCTAssertTrue(AccessibilityMode.reducedTransparency.reduceTransparency)
        XCTAssertFalse(AccessibilityMode.reducedTransparency.reduceMotion)
        XCTAssertTrue(AccessibilityMode.both.reduceMotion)
        XCTAssertTrue(AccessibilityMode.both.reduceTransparency)
    }

    func testHairlineDiffersBetweenGlassAndOpaque() {
        XCTAssertNotEqual(ARC.hairline(opaque: true), ARC.hairline(opaque: false))
    }

    // ── the accent drain ─────────────────────────────────────────────────────────────────────

    func testTheAccentDrainsToNeutralAndComesBack() {
        // A rule stated in the token table that nothing in the mockups implemented — `GeneratingView`
        // actively tinted its bar with the accent, which is the precise opposite.
        XCTAssertEqual(ARC.accent(drained: false).hexString, "B4552D")
        XCTAssertEqual(ARC.accent(drained: true).hexString, ARC.neutral.hexString)
        XCTAssertNotEqual(ARC.accent(drained: false).hexString, ARC.accent(drained: true).hexString)
    }

    // ── the floor ────────────────────────────────────────────────────────────────────────────

    func testTheHitTargetFloorIsFortyFour() {
        XCTAssertEqual(ARC.minimumHitTarget, 44)
    }

    func testTypeScalesRatherThanBeingFixed() {
        // `Font.system(size:weight:)` does NOT respond to Dynamic Type, and every style in the
        // handoff was spelled that way at the call site.
        for style in [ARC.TextStyle.title, .heading, .body, .cta, .subheading,
                      .secondary, .caption, .captionStrong, .micro, .label] {
            XCTAssertGreaterThan(style.size, 0)
            // Every style is anchored to a system text style, which is what `@ScaledMetric`
            // needs to scale it.
            XCTAssertNotNil(style.relativeTo)
        }
    }

    func testTheGridReflowsToOneColumnAtLargeType() {
        // AX5 with two preset columns cannot fit a preset's own name.
        XCTAssertEqual(columnCount(for: .large), 2)
        XCTAssertEqual(columnCount(for: .xxxLarge), 2)
        XCTAssertEqual(columnCount(for: .accessibility1), 1)
        XCTAssertEqual(columnCount(for: .accessibility5), 1)
    }

    private func columnCount(for size: DynamicTypeSize) -> Int {
        size >= .accessibility1 ? 1 : 2
    }
}

extension Color {
    /// The token's hex, for comparing against the design bundle without arithmetic.
    var hexString: String {
        #if os(iOS)
        let native = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        native.getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        guard let native = NSColor(self).usingColorSpace(.sRGB) else { return "?" }
        let r = native.redComponent, g = native.greenComponent, b = native.blueComponent
        #endif
        return String(format: "%02X%02X%02X",
                      Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}
