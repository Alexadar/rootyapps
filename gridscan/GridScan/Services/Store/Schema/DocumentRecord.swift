import Foundation
import SwiftData

// CloudKit-forward from day one: no @Attribute(.unique) (uniqueness is enforced in the
// store actor), relationships optional, attributes defaulted. The ScanDocument payload
// stays a JSON blob — the frozen Codable contract is never mirrored into @Model graphs.

@Model
final class DocumentRecord {
    var uuid: UUID = UUID()
    var title: String = ""
    var kindRaw: String = "table"
    var docDate: Date?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var pageCount: Int = 0
    var tableCount: Int = 0
    var unresolvedReviewCount: Int = 0
    var payloadVersion: Int = 1
    @Attribute(.externalStorage) var payload: Data = Data()
    @Relationship(deleteRule: .cascade, inverse: \ReviewFlagRecord.document)
    var flags: [ReviewFlagRecord]? = []
    // .nullify, not .cascade: the audit trail outlives document deletion by design.
    @Relationship(deleteRule: .nullify, inverse: \AuditEventRecord.document)
    var events: [AuditEventRecord]? = []

    init() {}
}
