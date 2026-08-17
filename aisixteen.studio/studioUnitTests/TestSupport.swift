import XCTest
import CoreGraphics
import RecipeKit
import EnhanceKit
import EditsKit
@testable import Studio

/// A small deterministic photo. Deliberately not flat: a flat field survives an unsharp mask
/// unchanged, so a test built on one would prove the enhancement does nothing.
@MainActor
func makePhoto(width: Int = 48, height: Int = 48) -> CGImage {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let i = (y * width + x) * 4
            pixels[i]     = UInt8((x * 255) / max(1, width - 1))
            pixels[i + 1] = UInt8((y * 255) / max(1, height - 1))
            pixels[i + 2] = UInt8(((x ^ y) * 5) % 256)
            pixels[i + 3] = 255
        }
    }
    return pixels.withUnsafeMutableBytes { raw in
        let context = CGContext(data: raw.baseAddress,
                                width: width,
                                height: height,
                                bitsPerComponent: 8,
                                bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        return context.makeImage()!
    }
}

/// A solid mask: white on the left half, black on the right. Exact halves, so a composite can be
/// checked column by column instead of by eye.
func makeHalfMask(width: Int = 48, height: Int = 48) -> CGImage {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let value: UInt8 = x < width / 2 ? 255 : 0
            let i = (y * width + x) * 4
            pixels[i] = value; pixels[i + 1] = value; pixels[i + 2] = value; pixels[i + 3] = 255
        }
    }
    return pixels.withUnsafeMutableBytes { raw in
        CGContext(data: raw.baseAddress,
                  width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!.makeImage()!
    }
}

func bytes(of image: CGImage) -> [UInt8] {
    RGBABuffer(image)!.pixels
}

func makeTemporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("StudioTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A library rooted in a throwaway folder, plus a record whose original is real bytes on disk.
@MainActor
func makeEditFixture(enhancer: any PhotoEnhancer = MockPhotoEnhancer(speed: .instant),
                     segmenter: any Segmenter = StubSegmenter(mask: makeHalfMask()))
-> (model: EditModel, library: EditLibrary, record: EditRecord) {
    let photo = makePhoto()
    let data = ImageCoder.encode(photo, as: .png)!
    let library = EditLibrary(root: makeTemporaryDirectory(),
                              access: DirectFileAccess(),
                              appVersion: "1.0")
    try! library.prepare()
    let record = try! library.create(originalData: data,
                                     fileExtension: "png",
                                     displayName: "IMG_4021",
                                     seed: 0xC0FFEE,
                                     createdAt: Date(timeIntervalSince1970: 1_786_000_000))

    let model = EditModel(original: photo,
                          record: record,
                          library: library,
                          // The provider ignores strength and shape: a test wants the enhancer it
                          // asked for, not one chosen by what is installed on the machine.
                          enhancer: { _, _ in enhancer },
                          segmenter: segmenter)
    return (model, library, record)
}

/// Stands in for Vision so the mask axis is deterministic and does not depend on what a 48 × 48
/// gradient happens to look like to a segmentation model.
struct StubSegmenter: Segmenter {
    let mask: CGImage?
    func subjectMask(for image: CGImage) async throws -> CGImage? { mask }
}

/// Never finds a subject — the landscape/wall/document case, which is a normal outcome and not an
/// error.
struct EmptySegmenter: Segmenter {
    func subjectMask(for image: CGImage) async throws -> CGImage? { nil }
}

/// Runs forever until cancelled, so a test can catch the job mid-pass.
final class HangingEnhancer: PhotoEnhancer {
    let plan = EnhancePlan.standard
    private let flag = NSLock()
    private var cancelled = false

    func cancel() { flag.lock(); cancelled = true; flag.unlock() }

    func enhance(photo: CGImage,
                 strength: Double,
                 mask: CGImage?,
                 seed: UInt32?,
                 progress: @escaping (EnhanceProgress) -> Void) async throws -> EnhancedPhoto {
        for step in 1...plan.totalSteps {
            try? await Task.sleep(for: .milliseconds(20))
            flag.lock(); let stop = cancelled; flag.unlock()
            if stop || Task.isCancelled { throw EnhanceError.cancelled }
            progress(EnhanceProgress(step: step, totalSteps: plan.totalSteps))
        }
        throw EnhanceError.cancelled
    }
}

/// Waits for a condition without sleeping a fixed amount, so a slow machine does not turn a passing
/// test into a flaky one.
@MainActor
func waitUntil(_ description: String,
               timeout: Duration = .seconds(5),
               file: StaticString = #filePath,
               line: UInt = #line,
               _ condition: @MainActor () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("timed out waiting for \(description)", file: file, line: line)
}
