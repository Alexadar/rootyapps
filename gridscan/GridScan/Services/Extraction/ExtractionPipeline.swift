import Foundation
import CoreGraphics
import PDFKit
import DocumentModelKit

/// Orchestrates page extraction → ScanDocument + ReviewFlags + per-page audit lines.
/// Image pages fan out in a TaskGroup (Vision requests are independent); PDF pages run
/// serially per document — PDFKit is not thread-safe.
actor ExtractionPipeline {

    struct Output: Sendable {
        var document: ScanDocument
        var flags: [ReviewFlag]
        var pageSourceLines: [String]
    }

    // MARK: images (camera scan or imported image files)

    func extract(images: [CGImage], documentID: UUID, defaultTitle: String) async -> Output {
        var extractions = [PageExtraction?](repeating: nil, count: images.count)
        await withTaskGroup(of: (Int, PageExtraction).self) { group in
            for (i, image) in images.enumerated() {
                group.addTask {
                    (i, await Self.extractImagePage(image, pageIndex: i))
                }
            }
            for await (i, extraction) in group { extractions[i] = extraction }
        }
        let sources = images.indices.map { "p.\($0 + 1) \(PageSource.ocr(.noTextLayer).auditDescription)" }
        return assemble(extractions.map { $0 ?? PageExtraction() },
                        documentID: documentID, defaultTitle: defaultTitle,
                        pageSourceLines: ["\(images.count) page(s) scanned \u{00B7} OCR"],
                        detailedSources: sources)
    }

    private static func extractImagePage(_ image: CGImage, pageIndex: Int) async -> PageExtraction {
        // Primary: document structure. Degrade to text clustering on error/empty.
        if let primary = try? await VisionAdapter.extract(image: image, pageIndex: pageIndex),
           !primary.tables.isEmpty || !primary.loose.isEmpty {
            return primary
        }
        return (try? await VisionFallbackAdapter.extract(image: image, pageIndex: pageIndex))
            ?? PageExtraction()
    }

    // MARK: PDF (branch per PAGE, never per file)

    func extract(pdfURL: URL, documentID: UUID, defaultTitle: String) async -> Output {
        guard let pdf = PDFDocument(url: pdfURL) else {
            return Output(document: ScanDocument(id: documentID, title: defaultTitle,
                                                 kind: .report),
                          flags: [], pageSourceLines: ["unreadable PDF"])
        }
        var extractions: [PageExtraction] = []
        var sourceLines: [String] = []
        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index) else {
                extractions.append(PageExtraction())
                continue
            }
            let cropBox = page.bounds(for: .cropBox)
            let source = PageSourceDecider.decide(
                text: page.string,
                wordBounds: PDFTextLayerAdapter.sampleBounds(on: page),
                cropBox: cropBox)
            sourceLines.append("p.\(index + 1) \(source.auditDescription)")

            switch source {
            case .textLayer:
                extractions.append(PDFTextLayerAdapter.extract(page: page, pageIndex: index))
                if let render = PDFPageRenderer.render(page: page, dpi: 144) {
                    _ = try? PageImageStore.writePage(render, index: index,
                                                      documentID: documentID)
                }
            case .ocr:
                if let render = PDFPageRenderer.render(page: page) {
                    _ = try? PageImageStore.writePage(render, index: index,
                                                      documentID: documentID)
                    extractions.append(await Self.extractImagePage(render, pageIndex: index))
                } else {
                    extractions.append(PageExtraction())
                }
            }
        }
        return assemble(extractions, documentID: documentID, defaultTitle: defaultTitle,
                        pageSourceLines: [sourceLines.joined(separator: " \u{00B7} ")],
                        detailedSources: sourceLines)
    }

    // MARK: assembly

    private func assemble(_ extractions: [PageExtraction], documentID: UUID,
                          defaultTitle: String, pageSourceLines: [String],
                          detailedSources: [String]) -> Output {
        var pages: [Page] = []
        var flags: [ReviewFlag] = []
        var titleGuess: String?

        for (index, extraction) in extractions.enumerated() {
            let page = Page(index: index, tables: extraction.tables,
                            looseText: extraction.loose)
            pages.append(page)
            if titleGuess == nil, let t = extraction.titleGuess, !t.isEmpty { titleGuess = t }

            for hit in extraction.lowConfidence {
                let address: FlagAddress
                let original: String
                switch hit {
                case .cell(let tableIndex, let row, let column, let text):
                    guard extraction.tables.indices.contains(tableIndex) else { continue }
                    address = .cell(CellAddress(documentID: documentID, pageIndex: index,
                                                tableID: extraction.tables[tableIndex].id,
                                                row: row, column: column))
                    original = text
                case .span(let id, let text):
                    address = .span(SpanAddress(documentID: documentID, pageIndex: index,
                                                spanID: id))
                    original = text
                }
                flags.append(ReviewFlag(id: UUID(), documentID: documentID,
                                        address: address, reason: .lowOCRConfidence,
                                        status: .open,
                                        originalText: "Read as \u{201C}\(original)\u{201D}",
                                        correctedText: nil))
            }
        }

        let document = ScanDocument(id: documentID,
                                    title: titleGuess ?? defaultTitle,
                                    kind: inferKind(of: pages),
                                    pages: pages)
        return Output(document: document, flags: flags,
                      pageSourceLines: pageSourceLines + detailedSources)
    }

    /// Structural kind describes layout SHAPE, never content meaning. User-editable later.
    private func inferKind(of pages: [Page]) -> DocumentKind {
        let tables = pages.reduce(0) { $0 + $1.tables.count }
        let spans = pages.reduce(0) { $0 + $1.looseText.count }
        if tables > 0 { return .table }
        guard spans > 0 else { return .report }
        let avgLen = pages.flatMap(\.looseText).reduce(0) { $0 + $1.text.count } / spans
        return (avgLen < 32 && spans >= 8) ? .form : .report
    }
}
