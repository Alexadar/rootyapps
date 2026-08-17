import Foundation
import CoreGraphics
import ImageIO
import DocumentModelKit

/// Entry point for both input routes. Owns the job: copy in → extract → persist →
/// audit → index. Nothing here presents UI; views call it after an explicit user tap.
final class ImportService: Sendable {

    let store: any DocumentStore
    let pipeline: ExtractionPipeline
    let indexer: SpotlightIndexer

    init(store: any DocumentStore, pipeline: ExtractionPipeline, indexer: SpotlightIndexer) {
        self.store = store
        self.pipeline = pipeline
        self.indexer = indexer
    }

    /// Camera scan pages (already perspective-corrected by VisionKit).
    func importScan(pages: [CGImage]) async {
        let docID = UUID()
        for (i, image) in pages.enumerated() {
            _ = try? PageImageStore.writePage(image, index: i, documentID: docID)
        }
        let output = await pipeline.extract(images: pages, documentID: docID,
                                            defaultTitle: defaultScanTitle())
        await persist(output, source: .camera)
    }

    /// File import (PDF or images), one document per file.
    func importFiles(urls: [URL]) async {
        for url in urls {
            let docID = UUID()
            do {
                let file = try FileImportValidator.copyIn(url, documentID: docID)
                let output: ExtractionPipeline.Output
                switch file.kind {
                case .pdf:
                    output = await pipeline.extract(pdfURL: file.localURL,
                                                    documentID: docID,
                                                    defaultTitle: file.originalName)
                case .image:
                    guard let image = Self.loadCGImage(file.localURL) else {
                        await recordFailure(name: file.originalName, docID: docID)
                        continue
                    }
                    _ = try? PageImageStore.writePage(image, index: 0, documentID: docID)
                    output = await pipeline.extract(images: [image], documentID: docID,
                                                    defaultTitle: file.originalName)
                }
                await persist(output, source: .file)
            } catch {
                PageImageStore.removeDirectory(documentID: docID)
                await recordFailure(name: url.lastPathComponent, docID: nil)
            }
        }
    }

    private func persist(_ output: ExtractionPipeline.Output, source: ImportSource) async {
        do {
            let summary = try await store.create(output.document, flags: output.flags,
                                                 source: source,
                                                 detailLines: output.pageSourceLines)
            await indexer.index(summary: summary, document: output.document)
        } catch {
            PageImageStore.removeDirectory(documentID: output.document.id)
            await recordFailure(name: output.document.title, docID: nil)
        }
    }

    private func recordFailure(name: String, docID: UUID?) async {
        try? await store.appendEvent(AuditEvent(
            id: UUID(), documentID: docID, kind: .importFailed, timestamp: .now,
            title: "Could not bring in \u{201C}\(name)\u{201D}",
            detailLines: ["The file was left untouched at its source."]))
    }

    private func defaultScanTitle() -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return "Scan \(fmt.string(from: .now))"
    }

    static func loadCGImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary)
    }
}
