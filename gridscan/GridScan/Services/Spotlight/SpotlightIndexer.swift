import Foundation
import CoreSpotlight
import DocumentModelKit

/// Donates documents to the system index (find the DOCUMENT — Apple-managed, 1.0).
/// Passage retrieval is v2 and does not live here.
final class SpotlightIndexer: Sendable {

    private let domain = "oleksandr.aisixteen.gridscan.documents"

    func index(summary: DocumentSummary, document: ScanDocument) async {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = summary.title
        attributes.contentDescription =
            "\(summary.pageCount) page(s) \u{00B7} \(summary.tableCount) table(s)"
        attributes.contentCreationDate = summary.date ?? summary.createdAt
        // A bounded slice of text content; the full grid is not Spotlight's job.
        attributes.textContent = document.allText.prefix(200).joined(separator: " ")
        let item = CSSearchableItem(uniqueIdentifier: summary.id.uuidString,
                                    domainIdentifier: domain,
                                    attributeSet: attributes)
        try? await CSSearchableIndex.default().indexSearchableItems([item])
    }

    func remove(ids: [UUID]) async {
        try? await CSSearchableIndex.default()
            .deleteSearchableItems(withIdentifiers: ids.map(\.uuidString))
    }
}
