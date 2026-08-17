import XCTest
import CoreGraphics
import LibraryKit
import GenerationKit
@testable import Wallpapers

/// The thumbnail cache, which is keyed by **id and size**.
///
/// The bug this exists to prevent already shipped once and was reported as "why does the preview
/// show a low quality thumb?". Two screens ask for the same wallpaper at different sizes — the
/// Create hero at 240 px, the gallery grid at 600 px — and with the id as the only key, whichever
/// asked first won. Opening on Create and then switching to Gallery gave a 240 px bitmap stretched
/// across a grid tile, which reads as the app having saved a bad picture rather than as a cache bug.
///
/// Nothing about it fails loudly, which is why it needs a test rather than an eye.
@MainActor
final class ThumbnailCacheChecks: XCTestCase {

    private func library() async throws -> (LibraryModel, LibraryModel.Item) {
        let root = makeTemporaryDirectory()
        let library = LibraryLocator.library(for: .local(root), appVersion: "1.0.0")
        try library.prepare()
        // 1024², so 240 and 600 are both genuine downsamples and visibly different sizes.
        let png = try XCTUnwrap(Bitmap.pngData(cg: Self.testPattern(side: 1024)))
        try library.save(imageData: png,
                         prompt: "a slate coastline under fog",
                         seed: 7,
                         aspect: .phone,
                         createdAt: Date(timeIntervalSince1970: 1_786_000_000))

        let model = LibraryModel(appVersion: "1.0.0")
        await model.start(at: .local(root))
        return (model, try XCTUnwrap(model.items.first, "the library did not come back"))
    }

    func testTwoSizesOfTheSameWallpaperAreCachedSeparately() async throws {
        let (model, item) = try await library()

        // The order that broke it: the small one first, then the large.
        let smallRaw = await model.thumbnail(for: item, maxPixel: 240)
        let small = try XCTUnwrap(smallRaw)
        let largeRaw = await model.thumbnail(for: item, maxPixel: 600)
        let large = try XCTUnwrap(largeRaw)

        XCTAssertEqual(max(small.pixelWidth, small.pixelHeight), 240)
        XCTAssertEqual(max(large.pixelWidth, large.pixelHeight), 600,
                       "the 600 px request was served the 240 px bitmap from the cache")
    }

    func testTheOtherOrderIsNoDifferent() async throws {
        let (model, item) = try await library()
        let largeRaw = await model.thumbnail(for: item, maxPixel: 600)
        let large = try XCTUnwrap(largeRaw)
        let smallRaw = await model.thumbnail(for: item, maxPixel: 240)
        let small = try XCTUnwrap(smallRaw)

        XCTAssertEqual(max(large.pixelWidth, large.pixelHeight), 600)
        XCTAssertEqual(max(small.pixelWidth, small.pixelHeight), 240,
                       "the 240 px request was served the 600 px bitmap")
    }

    func testASecondRequestAtTheSameSizeIsTheCachedOne() async throws {
        let (model, item) = try await library()
        let firstRaw = await model.thumbnail(for: item, maxPixel: 600)
        let first = try XCTUnwrap(firstRaw)
        let secondRaw = await model.thumbnail(for: item, maxPixel: 600)
        let second = try XCTUnwrap(secondRaw)
        XCTAssertTrue(first === second, "the cache is not caching")
    }

    func testInvalidatingDropsEverySizeNotJustTheOneThatWasAskedForLast() async throws {
        // Enhance rewrites the master at the same path, so the record does not change. If
        // invalidation only cleared one size, the gallery would keep showing the pre-enhance
        // picture — which is exactly the symptom that was reported.
        let (model, item) = try await library()
        let smallBeforeRaw = await model.thumbnail(for: item, maxPixel: 240)
        let smallBefore = try XCTUnwrap(smallBeforeRaw)
        let largeBeforeRaw = await model.thumbnail(for: item, maxPixel: 600)
        let largeBefore = try XCTUnwrap(largeBeforeRaw)

        await model.invalidate(item.id)
        let refreshed = try XCTUnwrap(model.items.first)

        let smallAfterRaw = await model.thumbnail(for: refreshed, maxPixel: 240)
        let smallAfter = try XCTUnwrap(smallAfterRaw)
        let largeAfterRaw = await model.thumbnail(for: refreshed, maxPixel: 600)
        let largeAfter = try XCTUnwrap(largeAfterRaw)
        XCTAssertFalse(smallBefore === smallAfter, "the 240 px entry survived invalidation")
        XCTAssertFalse(largeBefore === largeAfter, "the 600 px entry survived invalidation")
    }

    // MARK: -

    private static func testPattern(side: Int) -> CGImage {
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.setFillColor(CGColor(red: 0.9, green: 0.8, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side / 2, height: side / 2))
        return context.makeImage()!
    }
}

private extension PlatformImage {
    /// `NSImage.size` is in points and lies about what was decoded; the CGImage is the truth.
    var pixelWidth: Int { cgImageForRefinement?.width ?? 0 }
    var pixelHeight: Int { cgImageForRefinement?.height ?? 0 }
}
