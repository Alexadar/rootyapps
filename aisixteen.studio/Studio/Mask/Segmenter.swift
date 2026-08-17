import Foundation
import CoreGraphics
import CoreImage
import Vision

/// Produces the subject mask that `Subject` and `Background` both read.
///
/// A protocol because the mask has to be substitutable in tests — not because a second
/// implementation is planned. Vision's segmentation ships in the OS, runs on device and needs no
/// download, so unlike the diffusion pass this is **real from day one**.
protocol Segmenter: Sendable {
    /// White where the subject is. `nil` when the photo has no clear subject — a landscape, a wall,
    /// a document. That is a normal outcome, not an error, and the UI says so rather than offering
    /// a scope that would do nothing.
    func subjectMask(for image: CGImage) async throws -> CGImage?
}

/// The real one.
struct VisionSegmenter: Segmenter {

    func subjectMask(for image: CGImage) async throws -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        // Vision is synchronous and CPU-bound. Off the main actor, or picking a scope hitches the
        // whole interface on a large photo.
        try await Task.detached(priority: .userInitiated) {
            try handler.perform([request])
        }.value

        guard let observation = request.results?.first,
              !observation.allInstances.isEmpty else { return nil }

        // Every instance, not just the most prominent one: a photo of two people has two, and
        // "Subject" plainly means both of them.
        let buffer = try observation.generateScaledMaskForImage(forInstances: observation.allInstances,
                                                                from: handler)
        return Self.cgImage(from: buffer, matching: image)
    }

    /// Vision hands back a `CVPixelBuffer` at the source resolution; the compositor wants a
    /// `CGImage`. CoreImage does the conversion without a second pixel format to reason about.
    private static func cgImage(from buffer: CVPixelBuffer, matching image: CGImage) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let target = CGRect(x: 0, y: 0, width: image.width, height: image.height)

        // The scaled mask is already the source's aspect, but not always its exact pixel count.
        // Scaling here rather than in the compositor keeps the mask and the photo in one coordinate
        // system from this point on.
        let scale = CGAffineTransform(scaleX: target.width / ciImage.extent.width,
                                      y: target.height / ciImage.extent.height)
        return context.createCGImage(ciImage.transformed(by: scale), from: target)
    }
}

/// What a scope needs before it can be enhanced, and what to say when it cannot be.
enum MaskAvailability: Equatable {
    case ready
    /// Vision found nothing to separate.
    case noSubjectFound
    /// The brush scope with nothing painted yet.
    case nothingPainted
    case working

    var blockingMessage: String? {
        switch self {
        case .ready, .working:  return nil
        case .noSubjectFound:   return "No clear subject in this photo. Try Whole photo or Brush."
        case .nothingPainted:   return "Paint over the part you want enhanced."
        }
    }

    var allowsEnhance: Bool { self == .ready }
}
