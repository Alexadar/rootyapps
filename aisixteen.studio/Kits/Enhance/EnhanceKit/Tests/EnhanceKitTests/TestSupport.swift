import XCTest
import CoreGraphics
@testable import EnhanceKit

/// A small deterministic photo. Not flat: a flat field survives an unsharp mask unchanged, so a
/// test that used one would prove the enhancement does nothing.
func makePhoto(width: Int = 64, height: Int = 64) -> CGImage {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let i = (y * width + x) * 4
            pixels[i]     = UInt8((x * 255) / max(1, width - 1))
            pixels[i + 1] = UInt8((y * 255) / max(1, height - 1))
            pixels[i + 2] = UInt8(((x ^ y) * 3) % 256)
            pixels[i + 3] = 255
        }
    }
    return PixelImage(width: width, height: height, pixels: pixels).cgImage()!
}

func bytes(of image: CGImage) -> [UInt8] {
    PixelImage(image)!.pixels
}

/// Sum of absolute channel differences — "how far from the original", so a test can assert that a
/// louder detent moves further rather than merely differently.
func distance(_ a: [UInt8], _ b: [UInt8]) -> Int {
    zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
}

/// Collects progress from the enhancer's callback, which arrives off the test's thread.
final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var received: [(step: Int, previewWidth: Int?)] = []

    func record(_ progress: EnhanceProgress) {
        lock.lock(); defer { lock.unlock() }
        received.append((progress.step, progress.intermediate?.width))
    }

    var steps: [Int] {
        lock.lock(); defer { lock.unlock() }
        return received.map(\.step)
    }

    var previewSteps: [Int] {
        lock.lock(); defer { lock.unlock() }
        return received.filter { $0.previewWidth != nil }.map(\.step)
    }

    var previewWidths: [Int] {
        lock.lock(); defer { lock.unlock() }
        return received.compactMap(\.previewWidth)
    }
}

/// `XCTAssertThrowsError` does not take an async expression, so this is the async spelling — and it
/// checks the *specific* error, because "it threw something" would pass for a cancel that was
/// supposed to be a failure and vice versa.
func XCTAssertThrowsEnhanceError(_ expected: EnhanceError,
                                 file: StaticString = #filePath,
                                 line: UInt = #line,
                                 _ body: () async throws -> Void) async {
    do {
        try await body()
        XCTFail("expected \(expected), but the pass completed", file: file, line: line)
    } catch let error as EnhanceError {
        XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
        XCTFail("expected \(expected), got \(error)", file: file, line: line)
    }
}
