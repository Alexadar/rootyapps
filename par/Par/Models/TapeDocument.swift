import SwiftUI
import UniformTypeIdentifiers

public extension UTType {
    /// Must match the `UTExportedTypeDeclarations` entry in `project.yml` exactly — with no
    /// declaration behind it, `UTType(exportedAs:)` traps at launch. The identifier follows the
    /// registered bundle id (`oleksandr.aisixteen.fincalc`), not a generic reverse-DNS.
    static let parTape = UTType(exportedAs: "oleksandr.aisixteen.fincalc.tape")
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

    /// The bytes a damaged row was read from, kept verbatim so saving cannot destroy what we could
    /// not parse. Keyed by row id, never shown, never edited — a black box we hand straight back.
    private var quarantined: [UUID: Data] = [:]

    public init(title: String = "Untitled tape", rows: [TapeRow] = []) {
        self.title = title
        self.rows = rows
    }

    // MARK: - File format
    //
    // Rows are decoded ONE AT A TIME through an intermediate `[RawRow]`, so a single unreadable row
    // cannot take the document down. Decoding `[RowEnvelope]` directly would not do that: one bad
    // element throws for the whole array, and the "each row decodes independently" promise would
    // hold only for a payload that was already structurally perfect.

    private struct Payload: Codable {
        var version: Int
        var title: String
        var rows: [RawRow]
    }

    /// The parts every row has, plus the untouched bytes of the part that might not parse.
    private struct RawRow: Codable {
        var id: UUID
        var label: String
        var createdAt: Date
        var rawToolName: String
        var rawSummary: String
        /// Decoded lazily and defensively — see `decodedInputs()`.
        var inputs: FailableInputs
    }

    /// Decodes `SolveInputs` if it can, and keeps the raw JSON if it cannot. Both directions are
    /// lossless: re-encoding a row we could not read writes back exactly the bytes we were given.
    private struct FailableInputs: Codable {
        var value: SolveInputs?
        var raw: Data?

        init(_ value: SolveInputs) {
            self.value = value
            self.raw = nil
        }

        init(from decoder: Decoder) throws {
            // Capture the bytes first, so a failure still has something to hand back.
            let container = try decoder.singleValueContainer()
            if let decoded = try? container.decode(SolveInputs.self) {
                self.value = decoded
                self.raw = nil
            } else {
                self.value = nil
                self.raw = try? JSONSerialization.data(
                    withJSONObject: (try? container.decode(AnyCodable.self))?.value ?? [:]
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            if let value {
                try container.encode(value)
            } else if let raw, let object = try? JSONSerialization.jsonObject(with: raw) {
                try container.encode(AnyCodable(object))
            } else {
                try container.encodeNil()
            }
        }
    }

    /// Just enough of a dynamic JSON value to carry unparsed input bytes through a round trip.
    private struct AnyCodable: Codable {
        let value: Any

        init(_ value: Any) { self.value = value }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let object = try? container.decode([String: AnyCodable].self) {
                value = object.mapValues(\.value)
            } else if let array = try? container.decode([AnyCodable].self) {
                value = array.map(\.value)
            } else if let string = try? container.decode(String.self) {
                value = string
            } else if let number = try? container.decode(Double.self) {
                value = number
            } else if let flag = try? container.decode(Bool.self) {
                value = flag
            } else {
                value = [String: Any]()
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch value {
            case let dictionary as [String: Any]:
                try container.encode(dictionary.mapValues(AnyCodable.init))
            case let array as [Any]:
                try container.encode(array.map(AnyCodable.init))
            case let string as String: try container.encode(string)
            case let number as Double: try container.encode(number)
            case let number as Int: try container.encode(number)
            case let flag as Bool: try container.encode(flag)
            default: try container.encodeNil()
            }
        }
    }

    public init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let payload = try Self.decoder.decode(Payload.self, from: data)
        self.title = payload.title
        self.rows = payload.rows.map { raw in
            if let inputs = raw.inputs.value {
                return TapeRow(id: raw.id, label: raw.label,
                               inputs: inputs, createdAt: raw.createdAt)
            }
            // Surfaced, never trapped, never guessed — and the summary is preserved, because it is
            // the only description of the line the user has left.
            return TapeRow(
                id: raw.id,
                label: raw.label,
                inputs: .damaged(DamagedLine(
                    toolName: raw.rawToolName,
                    reason: "Stored inputs failed to decode.",
                    rawSummary: raw.rawSummary
                )),
                createdAt: raw.createdAt
            )
        }
        // Quarantine the unreadable bytes so a save round trip cannot lose them.
        //
        // `uniquingKeysWith` rather than `uniqueKeysWithValues`: two rows can share an id in a file
        // that was duplicated, merged badly or hand-edited, and the strict initialiser would trap on
        // the duplicate — crashing on open, which is precisely the "never let a decode failure
        // crash" promise this type makes. The first copy wins; the second still renders as a damaged
        // line, it just loses its quarantined bytes.
        self.quarantined = Dictionary(
            payload.rows.compactMap { raw in
                raw.inputs.value == nil ? raw.inputs.raw.map { (raw.id, $0) } : nil
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let payload = Payload(
            version: 1,
            title: title,
            rows: rows.map { row in
                if case .damaged(let damaged) = row.inputs {
                    // Write the original bytes back untouched. Re-encoding the *damage* would bake
                    // it in permanently: the line would then decode successfully as "damaged" and
                    // the real inputs would be gone for good.
                    var inputs = FailableInputs(row.inputs)
                    inputs.value = nil
                    inputs.raw = quarantined[row.id]
                    return RawRow(id: row.id, label: row.label, createdAt: row.createdAt,
                                  rawToolName: damaged.toolName, rawSummary: damaged.rawSummary,
                                  inputs: inputs)
                }
                return RawRow(id: row.id, label: row.label, createdAt: row.createdAt,
                              rawToolName: row.inputs.toolName,
                              rawSummary: TapeExport.summary(of: row),
                              inputs: FailableInputs(row.inputs))
            }
        )
        return FileWrapper(regularFileWithContents: try Self.encoder.encode(payload))
    }

    // MARK: - Coders
    //
    // ISO 8601 **with fractional seconds**, on both sides. Plain `.iso8601` has one-second
    // resolution, so a row stamped `.now` would not come back equal to itself after a reopen — the
    // tape would fail its own "timestamps survive a round trip" promise by a few hundred
    // milliseconds. Ordering would still be safe, but a claim that is only nearly true is the kind
    // this project does not ship.

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(iso8601.string(from: date))
        }
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = iso8601.date(from: text) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "not an ISO 8601 date with fractional seconds: \(text)"
                ))
            }
            return date
        }
        return decoder
    }()

    /// Appending is automatic and silent. The incumbent's failure was silent
    /// *loss*; Par's behaviour is silent *retention*. There is no save button.
    public mutating func append(_ row: TapeRow) {
        rows.append(row)
    }
}
