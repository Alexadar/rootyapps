import Foundation
import CoreGraphics
import Vision
import TableStructureKit

/// Fallback OCR path: plain RecognizeTextRequest observations → TextRun →
/// TableStructureKit clustering. Fully functional on its own so any surprise in the
/// primary API degrades here instead of blocking. Also the path for pre-26 revisions
/// of the document request returning nothing on a given image.
enum VisionFallbackAdapter {

    static func extract(image: CGImage, pageIndex: Int) async throws -> PageExtraction {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let observations = try await ImageRequestHandler(image).perform(request)

        var runs: [TextRun] = []
        var confidence: [TextRun: Float] = [:]
        for obs in observations {
            guard let candidate = obs.topCandidates(1).first else { continue }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let prov = CoordinateMapper.bbox(obs.boundingBox, pageIndex: pageIndex)
            let run = CoordinateMapper.textRun(text, prov: prov)
            runs.append(run)
            confidence[run] = candidate.confidence
        }
        return BlockAssembler.assemble(runs: runs, pageIndex: pageIndex,
                                       confidence: confidence)
    }
}
