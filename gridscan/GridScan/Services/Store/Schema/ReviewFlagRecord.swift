import Foundation
import SwiftData

@Model
final class ReviewFlagRecord {
    var uuid: UUID = UUID()
    var documentUUID: UUID = UUID()
    // Flattened address — queryable, no Codable blob. Cell: table/row/column set.
    // Loose-text span: spanUUID set.
    var pageIndex: Int = 0
    var tableUUID: UUID?
    var row: Int?
    var column: Int?
    var spanUUID: UUID?
    var reasonRaw: String = "lowOCRConfidence"
    var ruleDetail: String?
    var statusRaw: String = "open"
    var originalText: String?
    var correctedText: String?
    var createdAt: Date = Date.now
    var resolvedAt: Date?
    var document: DocumentRecord?

    init() {}
}
