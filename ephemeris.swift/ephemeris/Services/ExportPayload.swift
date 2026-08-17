import Foundation
import SwiftUI      // LocalizedStringKey for the format labels
import EphemerisKit

/// What an export will contain, resolved **before** anything is written or shared.
///
/// Separated from the sheet so the two things that matter can be tested without presenting UI: that
/// the summary a user is shown matches the bytes they get, and that nothing leaves the device.
///
/// ## The summary is a promise, not decoration
///
/// The sheet states a count and a date range before the user acts. If the summary is computed from
/// one set of events and the file from another — a filter applied after the count, a window that
/// moved while the sheet was open — the user is told one thing and given another, and neither the
/// number nor the file looks wrong on its own. So the payload owns both: `summary` and `data` read
/// the same stored array.
///
/// ## Formats
///
/// CSV and JSON, because those are what `TimelineExporter` produces and oracles. The design handoff
/// mentioned `.ics`; there is no ICS generator in the Kit, and inventing an unproven calendar
/// serializer to satisfy a doc would be the wrong way round — the doc is corrected instead.
///
/// ## Two kinds of content, because there are two kinds of thing to export
///
/// Events serialize through `TimelineExporter`. A saved chart does not: it is a `SavedChart`, whose
/// own `Codable` form is the file iCloud already syncs and `ChartStoreTests` already round-trips.
/// Exporting it means handing over that exact document, not re-deriving a lookalike.
///
/// ⚠️ The moon calendar exports **new and full moons only**. `AstroEvent.Kind` has no quarter
/// cases, and the CSV's `code` column is a stable published contract — inventing codes for the
/// quarters to make an export look complete would break every reader of an older file. The sheet
/// says what is included rather than quietly dropping half of it.
struct ExportPayload {

    enum Format: String, CaseIterable, Identifiable {
        case csv, json
        var id: String { rawValue }

        var fileExtension: String { rawValue }
        var uttype: String { self == .csv ? "public.comma-separated-values-text" : "public.json" }
        var label: LocalizedStringKey { self == .csv ? "CSV" : "JSON" }
    }

    /// What is being exported. Each case names its own file and its own row meaning.
    enum Subject: Equatable {
        /// The event timeline for a window.
        case events(String)
        /// One saved chart's events, named for the chart.
        case chart(String)
        /// Moon phases for a month.
        case moon(String)

        var identifier: String {
            switch self {
            case .events: "export.events"
            case .chart:  "export.chart"
            case .moon:   "export.moon"
            }
        }

        /// Filesystem-safe stem. Slashes and colons in a chart name would otherwise produce a file
        /// that silently fails to write on one platform and writes a nested path on another.
        var fileStem: String {
            let raw: String
            switch self {
            case .events(let s), .chart(let s), .moon(let s): raw = s
            }
            let cleaned = raw.map { $0.isLetter || $0.isNumber ? $0 : "-" }
            return String(cleaned).replacingOccurrences(of: "--", with: "-")
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
                .lowercased()
        }
    }

    /// What is actually serialized.
    enum Content {
        /// Events through `TimelineExporter`.
        case events([AstroEvent])
        /// A saved chart's own document — the same bytes iCloud stores.
        case chart(SavedChart)
    }

    let subject: Subject
    let content: Content
    let range: DateInterval

    var events: [AstroEvent] {
        if case .events(let e) = content { return e }
        return []
    }

    /// Rows a user is about to receive. A chart is one document, not a row count.
    var count: Int {
        switch content {
        case .events(let e): e.count
        case .chart:         1
        }
    }
    var isEmpty: Bool { count == 0 }

    /// A chart has one representation and it is JSON; offering CSV would produce a flattened
    /// lookalike that is not the document iCloud holds.
    var availableFormats: [Format] {
        switch content {
        case .events: Format.allCases
        case .chart:  [.json]
        }
    }

    func fileName(_ format: Format) -> String {
        "\(subject.fileStem.isEmpty ? "ephemeris" : subject.fileStem).\(format.fileExtension)"
    }

    /// The bytes. Reads the same `content` the summary counted.
    func data(_ format: Format) -> Data {
        switch content {
        case .events(let e):
            switch format {
            case .csv:  return Data(TimelineExporter.csv(e).utf8)
            case .json: return TimelineExporter.json(e, range: range)
            }
        case .chart(let chart):
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return (try? encoder.encode(chart)) ?? Data()
        }
    }

    /// The legend, offered alongside: the CSV carries stable event *codes*, which are meaningless
    /// without the table that names them.
    func legend(_ format: Format) -> Data {
        switch format {
        case .csv:  Data(TimelineExporter.legendCSV().utf8)
        case .json: TimelineExporter.legendJSON()
        }
    }

    /// The legend as a file, named so it cannot be confused with the data beside it.
    func writeLegend(_ format: Format) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("export", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("ephemeris-event-codes.\(format.fileExtension)")
        try legend(format).write(to: url, options: .atomic)
        return url
    }

    /// Writes both files to a temporary directory and returns their URLs, for `ShareLink` and for
    /// the macOS save panel.
    ///
    /// Temporary on purpose — the app never keeps a copy, and nothing is uploaded. Export is a
    /// hand-off to whatever the user chooses next.
    func writeTemporary(_ format: Format) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("export", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(fileName(format))
        try data(format).write(to: url, options: .atomic)
        return url
    }
}
