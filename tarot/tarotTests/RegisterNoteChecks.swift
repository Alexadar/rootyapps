import XCTest
@testable import Tarot

/// The one line of chrome that carries the app's register, pinned.
///
/// It is easy to soften a line like this in a design pass, and the cost of softening it is not a
/// design cost: the store description promises the same thing in the same words, and App Review
/// reads both. If the copy drifts, the listing and the product disagree — which is the 2.3.1
/// shape of problem, not a typo.
final class RegisterNoteChecks: XCTestCase {

    func testTheNoteSaysWhatTheTextIsAndIsNot() {
        let note = ReadingOverlay.registerNote
        XCTAssertTrue(note.lowercased().contains("not a prediction"),
                      "the note must deny prediction explicitly — got \(note)")
        XCTAssertTrue(note.lowercased().contains("interpretation"),
                      "the note must say what the text IS, not only what it is not — got \(note)")
    }

    /// "For entertainment purposes only" is the standard move in this category and Apple has
    /// closed it: Guideline 1.1.6 states that claiming entertainment purposes "won't overcome
    /// this guideline". A line like that buys no cover and reads as an admission that a forecast
    /// was implied, so it must not creep back in here or into the store copy.
    func testTheNoteIsNotAnEntertainmentPurposesDisclaimer() {
        let note = ReadingOverlay.registerNote.lowercased()
        for banned in ["entertainment purposes", "for entertainment", "novelty", "for fun only"] {
            XCTAssertFalse(note.contains(banned),
                           "\(banned) does not survive guideline 1.1.6 — say what the text is instead")
        }
    }

    /// The claim the note makes has to be the same claim the prompt enforces, or the app tells
    /// the reader one thing and asks the model for another.
    func testThePromptMakesTheSamePromiseTheNoteDoes() {
        let instructions = ReadingPrompt.instructions(deck: .classic1909, spread: .threeCard)
        XCTAssertTrue(instructions.contains("never predict the future"),
                      "the note promises no prediction; the instructions must demand it")
    }
}

/// The responsibility clause in Settings — said once, deliberately, away from the reading.
final class ResponsibilityNoteChecks: XCTestCase {

    func testItDisclaimsControlRatherThanSeriousness() {
        let n = SettingsSheet.responsibilityNote.lowercased()
        XCTAssertTrue(n.contains("does not predict the future"), n)
        XCTAssertTrue(n.contains("decisions you take"), "must place the decision with the reader: \(n)")
        XCTAssertTrue(n.contains("cannot tell you what to do"), n)
        XCTAssertTrue(n.contains("advice"), "must decline the advice categories: \(n)")
    }

    /// Neither Apple (1.1.6) nor UK consumer law accepts or requires this framing; it would be
    /// cargo-culting the category norm, which the market check showed to be a dead defence.
    func testItIsNotAnEntertainmentPurposesLabel() {
        let n = SettingsSheet.responsibilityNote.lowercased()
        for banned in ["entertainment purposes", "for entertainment", "novelty", "just for fun"] {
            XCTAssertFalse(n.contains(banned), "\(banned) overcomes nothing (Guideline 1.1.6)")
        }
    }
}

/// The auto-follow scroll. Two triggers, one animation — that is the whole invariant.
final class FollowScrollChecks: XCTestCase {

    /// Both call sites animate the same bottom anchor. When they used different durations
    /// (0.3 s and 0.9 s) each restarted the other mid-flight and the panel visibly stepped down
    /// the page. A test cannot see the judder, but it can pin the thing that caused it.
    func testBothTriggersShareOneAnimation() throws {
        let source = try String(contentsOfFile: overlayPath, encoding: .utf8)
        let calls = source.components(separatedBy: "proxy.scrollTo(\"reading.bottom\"").count - 1
        XCTAssertEqual(calls, 2, "expected exactly the two known auto-follow triggers")
        let viaConstant = source.components(separatedBy: "withAnimation(Self.follow)").count - 1
        XCTAssertEqual(viaConstant, 2,
                       "every auto-follow scroll must animate with Self.follow, not its own duration")
        XCTAssertFalse(source.contains("withAnimation(.linear(duration: 0.3))"),
                       "the short competing animation is what produced the stepping")
    }

    /// Linear, and long enough to bridge one wrapped line at the reveal's own pace. Easing would
    /// decelerate into every line break — the stutter this replaced.
    ///
    /// Asserted against the SOURCE, not `String(describing:)`. SwiftUI stores `.linear` as a
    /// BezierAnimation with a linear solver, so its description never contains the word "linear"
    /// — a mirror-based check fails on correct code, which is how this test first went red.
    func testTheFollowStepIsLinearAndBridgesALine() throws {
        let source = try String(contentsOfFile: overlayPath, encoding: .utf8)
        XCTAssertTrue(source.contains("static let follow: Animation = .linear(duration: 0.75)"),
                      "the follow step must stay linear and ~one wrapped line long")
    }

    private var overlayPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tarot/Chrome/ReadingOverlay.swift").path
    }
}

/// What replaced the install gate.
///
/// A capability gate was added and then removed (2026-08-19). It filtered GPU tier, which is a
/// proxy for the Apple Intelligence hardware line — but it could never cover the commonest case
/// of all: a perfectly capable device whose owner has Apple Intelligence switched off. That case
/// always fell through to the runtime check, which meant the gate was a second mechanism doing a
/// worse job of the first one's work, at the cost of most of the addressable market.
///
/// So the runtime check is now the ONLY mechanism, and these tests guard it accordingly.
final class AvailabilityHandlingChecks: XCTestCase {

    /// Four distinct reasons, four distinct messages. Collapsing them into one "unavailable"
    /// state is what makes an app look broken instead of unsupported.
    func testTheFourAvailabilityStatesStayDistinct() {
        let states: [WriterAvailability] = [.available, .deviceNotEligible, .notEnabled, .modelNotReady]
        XCTAssertEqual(Set(states).count, 4, "the four availability states must stay distinct")
    }

    /// The gate is gone: nothing may quietly reintroduce a device filter, because the app is
    /// meant to install anywhere and explain itself on hardware that cannot write.
    func testNoInstallGateIsDeclared() throws {
        let yml = try String(contentsOfFile: projectPath, encoding: .utf8)
        XCTAssertFalse(yml.contains("UIRequiredDeviceCapabilities"),
                       "a device gate is back; non-Apple-Intelligence devices should install and be told why")
        XCTAssertFalse(yml.contains("iphone-performance-gaming-tier"),
                       "the gaming-tier proxy is back; it also turns the app into a 'game' on iPad")
    }

    /// Kept for a build-quality reason, not an Apple Intelligence one — the RealityKit/Metal scene
    /// has never been run on Intel.
    func testTheMacBuildStaysAppleSiliconOnly() throws {
        let yml = try String(contentsOfFile: projectPath, encoding: .utf8)
        XCTAssertTrue(yml.contains("EXCLUDED_ARCHS[sdk=macosx*]: x86_64"),
                      "shipping an untested Intel slice for a Metal-heavy app risks crash-on-launch")
    }

    private var projectPath: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("project.yml").path
    }
}
