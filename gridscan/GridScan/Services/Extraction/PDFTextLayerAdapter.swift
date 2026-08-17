import Foundation
import PDFKit
import TableStructureKit

/// Born-digital pages: word-level positions straight from the PDF text layer — never
/// OCR'd. NOT thread-safe (PDFKit); the pipeline confines PDF work to one task.
enum PDFTextLayerAdapter {

    struct Word {
        let text: String
        let bounds: CGRect      // PDF points, bottom-left origin, page space
    }

    static func words(on page: PDFPage) -> [Word] {
        guard let pageText = page.string, !pageText.isEmpty else { return [] }
        var out: [Word] = []
        let ns = pageText as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length),
                               options: [.byWords, .substringNotRequired]) { _, range, _, _ in
            guard let selection = page.selection(for: range) else { return }
            let bounds = selection.bounds(for: page)
            guard bounds.width > 0, bounds.height > 0 else { return }
            out.append(Word(text: ns.substring(with: range), bounds: bounds))
        }
        return out
    }

    /// Cheap sample of word bounds for the garbage-layer geometry cross-check.
    static func sampleBounds(on page: PDFPage, limit: Int = 40) -> [CGRect] {
        var bounds: [CGRect] = []
        guard let pageText = page.string, !pageText.isEmpty else { return [] }
        let ns = pageText as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: min(ns.length, 4000)),
                               options: [.byWords, .substringNotRequired]) { _, range, _, stop in
            if let selection = page.selection(for: range) {
                bounds.append(selection.bounds(for: page))
            }
            if bounds.count >= limit { stop.pointee = true }
        }
        return bounds
    }

    /// Full text-layer extraction for one page → PageExtraction (top-left space).
    static func extract(page: PDFPage, pageIndex: Int) -> PageExtraction {
        let cropBox = page.bounds(for: .cropBox)
        let runs: [TextRun] = words(on: page).map { word in
            CoordinateMapper.textRun(
                word.text,
                prov: CoordinateMapper.bboxFromPDF(word.bounds, cropBox: cropBox,
                                                   pageIndex: pageIndex))
        }
        // No confidence map: a text layer has no OCR, so no OCR flags can exist here.
        return BlockAssembler.assemble(runs: runs, pageIndex: pageIndex)
    }
}
