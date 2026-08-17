import XCTest
import CoreGraphics
import RecipeKit
@testable import Studio

/// **The bit-for-bit promise, at the layer that keeps it.**
///
/// `RecipeKit` decides *that* zero means the original; this decides that the renderer hands back the
/// original image itself rather than recomputing something that merely looks the same.
final class CompositorChecks: XCTestCase {

    @MainActor
    func testTheOriginalCaseReturnsTheVeryImageItWasGivenNotACopy() {
        let original = makePhoto()
        let pass = makePhoto(width: 48, height: 48)

        let rendered = PhotoCompositor.render(original: original,
                                              pass: pass,
                                              composite: .original,
                                              masks: [:])

        // Identity, not equality. A composite at alpha 0 would satisfy `==` on the pixels most of
        // the time and quietly fail the one time a channel rounded the other way.
        XCTAssertTrue(rendered === original,
                      "strength 0 must skip the pipeline entirely, not run it with no effect")
    }

    @MainActor
    func testAFullBlendWithNoMaskIsThePassItself() {
        let original = makePhoto()
        let pass = makeHalfMask()          // a deliberately very different picture

        let rendered = PhotoCompositor.render(
            original: original,
            pass: pass,
            composite: .blended([.init(scope: .whole, mask: nil, fraction: 1)]),
            masks: [:])

        XCTAssertEqual(bytes(of: rendered), bytes(of: pass))
    }

    @MainActor
    func testAHalfBlendSitsBetweenTheTwo() {
        let original = makePhoto()
        let pass = makeHalfMask()

        let rendered = PhotoCompositor.render(
            original: original,
            pass: pass,
            composite: .blended([.init(scope: .whole, mask: nil, fraction: 0.5)]),
            masks: [:])

        let a = bytes(of: original), b = bytes(of: pass), mixed = bytes(of: rendered)
        for index in stride(from: 0, to: mixed.count, by: 4) {
            let expected = (Double(a[index]) + Double(b[index])) / 2
            XCTAssertEqual(Double(mixed[index]), expected, accuracy: 1)
        }
    }

    @MainActor
    func testAMaskConfinesThePassToWhereItIsWhite() {
        let original = makePhoto()
        let pass = makeHalfMask()
        let mask = makeHalfMask()          // white on the left, black on the right

        let rendered = PhotoCompositor.render(
            original: original,
            pass: pass,
            composite: .blended([.init(scope: .subject,
                                       mask: MaskRef(source: .segmentation, inverted: false),
                                       fraction: 1)]),
            masks: [.segmentation: mask])

        let before = bytes(of: original), after = bytes(of: rendered), passed = bytes(of: pass)
        let width = original.width
        for y in 0..<original.height {
            let left = (y * width + 2) * 4
            let right = (y * width + width - 3) * 4
            XCTAssertEqual(after[left], passed[left], "masked-in column should be the pass")
            XCTAssertEqual(after[right], before[right], "masked-out column must be untouched")
        }
    }

    @MainActor
    func testInvertingTheMaskSwapsExactlyWhichSideMoves() {
        let original = makePhoto()
        let pass = makeHalfMask()
        let mask = makeHalfMask()

        func render(inverted: Bool) -> [UInt8] {
            bytes(of: PhotoCompositor.render(
                original: original,
                pass: pass,
                composite: .blended([.init(scope: inverted ? .background : .subject,
                                           mask: MaskRef(source: .segmentation, inverted: inverted),
                                           fraction: 1)]),
                masks: [.segmentation: mask]))
        }

        let subject = render(inverted: false)
        let background = render(inverted: true)
        let before = bytes(of: original)
        let width = original.width

        for y in 0..<original.height {
            let left = (y * width + 2) * 4
            let right = (y * width + width - 3) * 4
            XCTAssertNotEqual(subject[left], before[left])
            XCTAssertEqual(subject[right], before[right])
            XCTAssertEqual(background[left], before[left])
            XCTAssertNotEqual(background[right], before[right])
        }
    }

    @MainActor
    func testAMaskedScopeWithNoMaskYetPaintsNothingRatherThanEverything() {
        let original = makePhoto()
        let pass = makeHalfMask()

        let rendered = PhotoCompositor.render(
            original: original,
            pass: pass,
            composite: .blended([.init(scope: .subject,
                                       mask: MaskRef(source: .segmentation, inverted: false),
                                       fraction: 1)]),
            masks: [:])          // the mask has not been computed yet

        XCTAssertEqual(bytes(of: rendered), bytes(of: original),
                       "falling back to the whole frame would turn \"subject only\" into "
                       + "\"everything\", which is the one mistake a user would not forgive")
    }

    @MainActor
    func testWithNoPassAtAllThereIsNothingToBlendAndTheOriginalComesBack() {
        let original = makePhoto()
        let rendered = PhotoCompositor.render(
            original: original,
            pass: nil,
            composite: .blended([.init(scope: .whole, mask: nil, fraction: 1)]),
            masks: [:])

        XCTAssertTrue(rendered === original)
    }

    @MainActor
    func testComposedLayersEachLandInTheirOwnArea() {
        let original = makePhoto()
        let pass = makeHalfMask()
        let mask = makeHalfMask()

        let rendered = PhotoCompositor.render(
            original: original,
            pass: pass,
            composite: .blended([
                .init(scope: .background,
                      mask: MaskRef(source: .segmentation, inverted: true), fraction: 1),
                .init(scope: .subject,
                      mask: MaskRef(source: .segmentation, inverted: false), fraction: 0.5),
            ]),
            masks: [.segmentation: mask])

        let before = bytes(of: original), after = bytes(of: rendered), passed = bytes(of: pass)
        let width = original.width
        let left = (3 * width + 2) * 4
        let right = (3 * width + width - 3) * 4

        XCTAssertEqual(Double(after[left]),
                       (Double(before[left]) + Double(passed[left])) / 2, accuracy: 1,
                       "subject half blended at 0.5")
        XCTAssertEqual(after[right], passed[right], "background half at full strength")
    }
}
