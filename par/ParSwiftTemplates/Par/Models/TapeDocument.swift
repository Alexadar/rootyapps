import SwiftUI
import UniformTypeIdentifiers

public extension UTType {
    static let parTape = UTType(exportedAs: "com.par.tape")
}

/// Tapes are documents — named, listed, reopened via `DocumentGroup`.
///
/// Nothing here is device-local, so an iCloud container can be switched on later
/// with no migration. iCloud sync is deliberately not in v1; when it arrives the
/// requirement is absolute (the same tape, complete and current, on all three
/// platforms), so nothing in this type may assume a single device.
public struct TapeDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.parTape] }

    public var title: String
    public var rows: [TapeRow]

    public init(title: String = "Untitled tape", rows: [TapeRow] = []) {
        self.title = title
        self.rows = rows
    }

    private struct Payload: Codable {
        var version: Int
        var title: String
        var rows: [RowEnvelope]
    }

    /// Each row decodes independently, so ONE damaged line cannot take the
    /// document down with it.
    private struct RowEnvelope: Codable {
        var id: UUID
        var label: String
        var createdAt: Date
        var inputs: SolveInputs?
        var rawToolName: String
        var rawSummary: String
    }

    public init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        self.title = payload.title
        self.rows = payload.rows.map { envelope in
            if let inputs = envelope.inputs {
                return TapeRow(id: envelope.id, label: envelope.label,
                               inputs: inputs, createdAt: envelope.createdAt)
            }
            // Surfaced, never trapped, never guessed.
            return TapeRow(
                id: envelope.id,
                label: envelope.label,
                inputs: .damaged(DamagedLine(
                    toolName: envelope.rawToolName,
                    reason: "Stored inputs failed to decode.",
                    rawSummary: envelope.rawSummary
                )),
                createdAt: envelope.createdAt
            )
        }
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let payload = Payload(
            version: 1,
            title: title,
            rows: rows.map { row in
                RowEnvelope(id: row.id, label: row.label, createdAt: row.createdAt,
                            inputs: row.inputs, rawToolName: row.inputs.toolName, rawSummary: "")
            }
        )
        let data = try JSONEncoder().encode(payload)
        return FileWrapper(regularFileWithContents: data)
    }

    /// Appending is automatic and silent. The incumbent's failure was silent
    /// *loss*; Par's behaviour is silent *retention*. There is no save button.
    public mutating func append(_ row: TapeRow) {
        rows.append(row)
    }
}
