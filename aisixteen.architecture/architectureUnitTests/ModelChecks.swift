import DirectionKit
import RedesignKit
import SwiftUI
import XCTest
@testable import Architecture

/// Direction — including the axis that shipped broken.
@MainActor
final class DirectionModelChecks: XCTestCase {

    func testTheModeComesFromTheShotAndReachesBothPresetSets() {
        // The regression: `DirectionView` shipped `let mode: SpaceMode = .interior`, so the
        // exterior presets were dead code nothing in the app could reach.
        let interior = DirectionModel(shot: Fixtures.shot(mode: .interior))
        XCTAssertEqual(interior.mode, .interior)
        XCTAssertEqual(interior.presets.map(\.id), ["scandi", "midcentury", "industrial", "japandi"])

        let exterior = DirectionModel(shot: Fixtures.shot(mode: .exterior))
        XCTAssertEqual(exterior.mode, .exterior)
        XCTAssertEqual(exterior.presets.map(\.id),
                       ["farmhouse", "georgian", "mediterranean", "minimalRender"])
        XCTAssertEqual(exterior.selectedPresetID, "farmhouse")
    }

    func testEveryVariationCountChangesTheCta() {
        let model = DirectionModel(shot: Fixtures.shot())
        var seen = Set<String>()
        for count in 1...5 {
            model.variations = count
            seen.insert(model.ctaTitle)
            XCTAssertTrue(model.ctaTitle.contains("min"))
        }
        XCTAssertEqual(seen.count, 5, "each count must price differently")
        model.variations = 1
        XCTAssertEqual(model.variationLine, "1 variation")
        model.variations = 3
        XCTAssertEqual(model.variationLine, "3 variations")
    }

    func testTheCtaUsesTheSeededFigureUntilSomethingIsMeasured() {
        let model = DirectionModel(shot: Fixtures.shot())
        model.variations = 3
        XCTAssertEqual(model.ctaTitle, "Redesign · ~6 min total")

        // Once a real run has been timed the CTA follows it.
        model.measuredSecondsPerVariation = 200
        XCTAssertEqual(model.ctaTitle, "Redesign · ~10 min total")
    }

    func testEditingThenRepickingOffersAnUndo() {
        let model = DirectionModel(shot: Fixtures.shot())
        model.edit("A calm room with a green sofa")
        XCTAssertTrue(model.recipe.isEdited)

        model.select(PresetCatalog.preset(id: "japandi")!)
        XCTAssertEqual(model.selectedPresetID, "japandi")
        XCTAssertFalse(model.recipe.isEdited)

        model.undoRepick()
        XCTAssertEqual(model.prompt, "A calm room with a green sofa")
    }

    func testChipsDisappearAsTheyAreUsedAndComeBackWhenRemoved() {
        let model = DirectionModel(shot: Fixtures.shot())
        XCTAssertEqual(model.availableChips.count, 3)
        model.append(.morePlants)
        XCTAssertEqual(model.availableChips.count, 2)
        model.append(.morePlants)
        XCTAssertEqual(model.availableChips.count, 2, "a chip appends once, however many taps")
        model.edit(PresetCatalog.preset(id: "scandi")!.prompt)
        XCTAssertEqual(model.availableChips.count, 3)
    }

    func testTheDepthBadgeDiffersPerSourceAndNeverClaimsAMeasurement() {
        let forbidden = ["measure", "dimension", "metre", "meter", "feet", "inch", "area"]
        var seen = Set<String>()
        for provenance in RedesignKit.DepthProvenance.allCases {
            let model = DirectionModel(shot: Fixtures.shot(provenance: provenance))
            seen.insert(model.depthBadge)
            for word in forbidden {
                XCTAssertFalse(model.depthBadge.lowercased().contains(word),
                               "\(provenance) badge claims a measurement")
            }
        }
        XCTAssertGreaterThanOrEqual(seen.count, 3, "the sources are not equally good and must not read alike")

        // No depth at all is its own honest state, and does not block the CTA.
        let none = DirectionModel(shot: Fixtures.shot(withDepth: false))
        XCTAssertEqual(none.depthBadge, "No depth — geometry may shift")
        XCTAssertFalse(none.depthIsMeasured)
        XCTAssertTrue(none.canStart)
    }

    func testAnEmptyPromptCannotStartARender() {
        let model = DirectionModel(shot: Fixtures.shot())
        model.edit("   ")
        XCTAssertFalse(model.canStart)
        model.edit("A bright room")
        XCTAssertTrue(model.canStart)
    }
}

/// The comparison's rules — every one of them without touching a gesture.
@MainActor
final class ResultModelChecks: XCTestCase {

    func testWipeClampsSoNeitherSideEverVanishes() {
        let model = ResultModel()
        model.set(-5)
        XCTAssertEqual(model.wipe, ResultModel.minimum)
        model.set(5)
        XCTAssertEqual(model.wipe, ResultModel.maximum)
    }

    func testTheAnnouncedPercentageMatchesWhatIsRevealed() {
        let model = ResultModel(wipe: 0.6)
        XCTAssertEqual(model.revealedPercent, 60)
        XCTAssertEqual(model.revealedWidthFraction, 0.6)
    }

    func testVoiceOverAdjustsByTenPercentInBothDirections() {
        let model = ResultModel(wipe: 0.5)
        model.adjust(revealMore: true)
        XCTAssertEqual(model.wipe, 0.6, accuracy: 0.0001)
        model.adjust(revealMore: false)
        XCTAssertEqual(model.wipe, 0.5, accuracy: 0.0001)

        // And it cannot be walked off either end.
        for _ in 0..<20 { model.adjust(revealMore: true) }
        XCTAssertEqual(model.wipe, ResultModel.maximum, accuracy: 0.0001)
        for _ in 0..<40 { model.adjust(revealMore: false) }
        XCTAssertEqual(model.wipe, ResultModel.minimum, accuracy: 0.0001)
    }

    func testFlipGoesToWhicheverEndIsFurtherAway() {
        let model = ResultModel(wipe: 0.2)
        model.flip(reduceMotion: true)
        XCTAssertEqual(model.wipe, ResultModel.maximum)
        model.flip(reduceMotion: true)
        XCTAssertEqual(model.wipe, ResultModel.minimum)
    }

    func testATapFlipsAndADragDoesNot() {
        // The two behaviours share one recogniser, so telling them apart is a real rule and not a
        // gesture-arena accident.
        // Starting past the midpoint, a flip goes to the near end — the divider travels to
        // whichever side it was NOT already showing more of.
        let tapped = ResultModel(wipe: 0.55)
        tapped.dragChanged(locationX: 100, translationX: 0, width: 400, reduceMotion: true)
        tapped.dragEnded(translationX: 1, width: 400, reduceMotion: true)
        XCTAssertEqual(tapped.wipe, ResultModel.minimum, "a tap under the threshold flips")

        let fromTheOtherEnd = ResultModel(wipe: 0.2)
        fromTheOtherEnd.dragChanged(locationX: 100, translationX: 0, width: 400, reduceMotion: true)
        fromTheOtherEnd.dragEnded(translationX: 1, width: 400, reduceMotion: true)
        XCTAssertEqual(fromTheOtherEnd.wipe, ResultModel.maximum)

        let dragged = ResultModel(wipe: 0.55)
        dragged.dragChanged(locationX: 320, translationX: 80, width: 400, reduceMotion: true)
        dragged.dragEnded(translationX: 80, width: 400, reduceMotion: true)
        XCTAssertEqual(dragged.wipe, 0.8, accuracy: 0.0001, "a drag wipes and does not flip")
    }

    func testPeekRestoresTheDividerExactly() async {
        // A peek that nudges the divider makes the comparison untrustworthy, which is the one
        // thing it cannot be.
        let model = ResultModel(wipe: 0.42)
        model.dragChanged(locationX: 200, translationX: 0, width: 400, reduceMotion: true)
        try? await Task.sleep(for: .milliseconds(320))
        XCTAssertTrue(model.isPeeking)
        XCTAssertEqual(model.revealedWidthFraction, 0, "peeking shows the original, uninterrupted")

        model.dragEnded(translationX: 0, width: 400, reduceMotion: true)
        XCTAssertFalse(model.isPeeking)
        XCTAssertEqual(model.wipe, 0.42, accuracy: 0.0001)
    }

    func testMovingCancelsAPendingPeek() async {
        let model = ResultModel(wipe: 0.5)
        model.dragChanged(locationX: 200, translationX: 0, width: 400, reduceMotion: true)
        model.dragChanged(locationX: 280, translationX: 80, width: 400, reduceMotion: true)
        try? await Task.sleep(for: .milliseconds(320))
        XCTAssertFalse(model.isPeeking, "a wipe must never turn into a peek halfway through")
    }
}

/// Capture, including the configurations that are easy to forget are configurations.
@MainActor
final class CaptureModelChecks: XCTestCase {

    func testTheSimulatorPathProducesAUsableShot() async {
        let model = CaptureModel(session: SimulatedCameraSession())
        await model.start()
        let shot = await model.capture()

        XCTAssertNotNil(shot)
        XCTAssertTrue(shot?.hasDepth ?? false)
        // Never `.estimated`: that would put "Depth estimated — geometry will hold" over a
        // gradient, which is a claim about a model that has not run.
        XCTAssertEqual(shot?.provenance, .synthetic)
        model.stop()
    }

    func testNoCameraDegradesToImportRatherThanAnErrorScreen() {
        // Somebody who declined the camera can still redesign a photo they already have.
        let model = CaptureModel(session: ImportOnlySession())
        XCTAssertFalse(model.canCapture)
        XCTAssertFalse(model.canSwitchCamera)
        XCTAssertNotNil(model.coach)
    }

    func testTheModeTravelsOntoTheShot() async {
        let model = CaptureModel(session: SimulatedCameraSession())
        await model.start()
        model.mode = .exterior
        let shot = await model.capture()
        XCTAssertEqual(shot?.mode, .exterior)
        model.stop()
    }

    func testTheCoachReachesEveryStateInBothDirections() {
        // The mockup's `coach` and `shotUsable` were `@State` constants that nothing ever mutated,
        // so the amber branch had never been seen by anything, including a person.
        let level = CoachLine.evaluate(mode: .interior, roll: 0, pitch: 0,
                                       nearestDisparity: 0.4, relativeLight: 0.8)
        XCTAssertTrue(level.isUsable)
        XCTAssertEqual(level.text, "Level · whole wall in frame · good light")

        let tilted = CoachLine.evaluate(mode: .interior, roll: 20, pitch: 0,
                                        nearestDisparity: 0.4, relativeLight: 0.8)
        XCTAssertFalse(tilted.isUsable)
        XCTAssertEqual(tilted.text, "Hold level")

        let close = CoachLine.evaluate(mode: .interior, roll: 0, pitch: 0,
                                       nearestDisparity: 0.95, relativeLight: 0.8)
        XCTAssertEqual(close.text, "Step back")

        let dark = CoachLine.evaluate(mode: .interior, roll: 0, pitch: 0,
                                      nearestDisparity: 0.4, relativeLight: 0.05)
        XCTAssertEqual(dark.text, "Needs more light")

        // And back to usable, which is the direction that never gets tested.
        let recovered = CoachLine.evaluate(mode: .interior, roll: 2, pitch: -3,
                                           nearestDisparity: 0.4, relativeLight: 0.9)
        XCTAssertTrue(recovered.isUsable)
    }

    func testExteriorGetsItsOwnFramingAdvice() {
        // You back away from a facade; you cannot back away from a wall.
        XCTAssertNotEqual(CoachLine.idleText(.interior), CoachLine.idleText(.exterior))
        XCTAssertTrue(CoachLine.idleText(.exterior).lowercased().contains("facade"))
    }

    func testNoDepthReadingMeansNoDistanceComplaint() {
        // An imported flat photo has no depth, and the coach must not invent a distance fault.
        let line = CoachLine.evaluate(mode: .interior, roll: 0, pitch: 0,
                                      nearestDisparity: nil, relativeLight: 0.8)
        XCTAssertTrue(line.isUsable)
    }
}

/// The router — the thing the handoff had no version of at all.
@MainActor
final class RouterChecks: XCTestCase {

    func testTheFlowAdvancesAndComesBack() {
        let router = Router()
        XCTAssertEqual(router.stage, .capture)

        let shot = Fixtures.shot()
        router.begin(shot)
        XCTAssertEqual(router.stage, .direction(shot))

        router.started(projectID: "p1")
        XCTAssertTrue(router.stage.isGenerating)

        router.finished(projectID: "p1", variation: 1)
        XCTAssertEqual(router.stage, .result(projectID: "p1", variation: 1))
    }

    func testStartingAJobDoesNotStealTheLibrary() {
        // The queue keeps running while the user browses, which is why section and stage are
        // independent rather than one enum.
        let router = Router()
        router.openLibrary()
        router.started(projectID: "p1")
        XCTAssertEqual(router.section, .redesign)

        router.openLibrary()
        XCTAssertEqual(router.section, .library)
        XCTAssertTrue(router.stage.isGenerating, "the flow keeps its place")
    }

    func testFinishingOnlyRoutesIfTheUserIsStillWatching() {
        let router = Router()
        router.started(projectID: "p1")
        router.openLibrary()

        router.finished(projectID: "p1", variation: 1)
        // Somebody who wandered off did not ask to be yanked back mid-scroll.
        XCTAssertEqual(router.section, .library)
        XCTAssertTrue(router.stage.isGenerating)

        // But a deliberate open does go there.
        router.openResult(projectID: "p1", variation: 1)
        XCTAssertEqual(router.section, .redesign)
        XCTAssertEqual(router.stage, .result(projectID: "p1", variation: 1))
    }

    func testFinishingADifferentProjectNeverRoutes() {
        let router = Router()
        router.started(projectID: "p1")
        router.finished(projectID: "p2", variation: 1)
        XCTAssertTrue(router.stage.isGenerating)
    }

    func testBackFromEachStageGoesSomewhereSensible() {
        let router = Router()
        router.begin(Fixtures.shot())
        router.back()
        XCTAssertEqual(router.stage, .capture)

        router.openResult(projectID: "p1", variation: 2)
        router.back()
        XCTAssertEqual(router.section, .library)
        XCTAssertEqual(router.selectedProjectID, "p1")
    }
}
