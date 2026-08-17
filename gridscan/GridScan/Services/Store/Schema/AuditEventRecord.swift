import Foundation
import SwiftData

@Model
final class AuditEventRecord {
    var uuid: UUID = UUID()
    var documentUUID: UUID?         // nullable: the trail outlives document deletion
    var kindRaw: String = "imported"
    var timestamp: Date = Date.now
    var title: String = ""
    var detailBlob: String = ""     // detail lines joined by \n (CloudKit-friendly scalar)
    var document: DocumentRecord?

    var detailLines: [String] {
        get { detailBlob.isEmpty ? [] : detailBlob.components(separatedBy: "\n") }
        set { detailBlob = newValue.joined(separator: "\n") }
    }

    init() {}
}
