import SwiftUI
import UniformTypeIdentifiers
import UnitsKit
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Results bubbling up from wherever a tool drew them, so the toolbar can copy and export without
/// each tool having to hand its numbers to its own chrome.
struct ResultRowsKey: PreferenceKey {
    static var defaultValue: [ResultGrid.Row] = []

    static func reduce(value: inout [ResultGrid.Row], nextValue: () -> [ResultGrid.Row]) {
        value.append(contentsOf: nextValue())
    }
}

/// Getting results out.
///
/// ## Why this is a first-class feature and not a nicety
///
/// The Mac user is writing up a job. A calculator that can only be read off the screen makes them
/// retype every number into a report, which is both slow and where transcription errors come from.
/// So: copy one value, copy the whole table, or export a CSV — and the CSV carries the units and
/// the site elevation, because a column of numbers with no units is not a record of anything.
enum Export {

    /// Tab-separated, which is what spreadsheets expect from the clipboard.
    static func table(_ rows: [ResultGrid.Row], system: UnitSystem) -> String {
        let header = "Property\tValue\tUnit"
        let body = rows.map { row in
            "\(row.title)\t\(Fmt.exportValue(si: row.value, row.quantity, system))"
            + "\t\(row.quantity.symbol(system))"
        }
        return ([header] + body).joined(separator: "\n")
    }

    /// CSV, with a provenance header. The elevation is in there because the same inputs at a
    /// different elevation are different answers, and a file that does not say which is a file
    /// that cannot be checked later.
    static func csv(_ rows: [ResultGrid.Row], tool: Tool, system: UnitSystem,
                    elevationMetres: Double) -> String {
        var lines = [
            "# AirCore — \(tool.plainTitle)",
            "# Units,\(system.rawValue)",
            "# Site elevation,"
                + quoted(Fmt.exportValueWithUnit(si: elevationMetres, .elevation, system)),
            "Property,Value,Unit",
        ]
        lines += rows.map { row in
            let value = Fmt.exportValue(si: row.value, row.quantity, system)
            return "\(quoted(row.title)),\(quoted(value)),\(quoted(row.quantity.symbol(system)))"
        }
        return lines.joined(separator: "\n")
    }

    /// A field containing a comma, a quote or a newline has to be quoted, or the file is not CSV.
    /// Unit symbols contain slashes and superscripts and one of them ("in wg/100 ft") has a space;
    /// none of those need quoting, but a localised decimal comma does.
    private static func quoted(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    static func copyToPasteboard(_ text: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
}

/// A CSV document, for `.fileExporter` and for dragging a state set out to Finder or Numbers.
struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    let text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let decoded = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = decoded
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// Copy and export, in the toolbar of every tool.
struct ExportControls: View {

    let tool: Tool
    let rows: [ResultGrid.Row]

    @Environment(AppSettings.self) private var settings
    @State private var isExporting = false

    private var csv: String {
        Export.csv(rows, tool: tool, system: settings.unitSystem,
                   elevationMetres: settings.elevationMetres)
    }

    var body: some View {
        Group {
            Button {
                Export.copyToPasteboard(Export.table(rows, system: settings.unitSystem))
            } label: {
                Label("Copy table", systemImage: "doc.on.doc")
            }
            .disabled(rows.isEmpty)
            .accessibilityIdentifier("export.copyTable")

            Button {
                isExporting = true
            } label: {
                Label("Export CSV", systemImage: "square.and.arrow.up")
            }
            .disabled(rows.isEmpty)
            .accessibilityIdentifier("export.csv")
        }
        .fileExporter(isPresented: $isExporting,
                      document: CSVDocument(text: csv),
                      contentType: .commaSeparatedText,
                      defaultFilename: "AirCore \(tool.plainTitle)") { _ in }
        .onReceive(NotificationCenter.default.publisher(for: .copyTable)) { _ in
            guard !rows.isEmpty else { return }
            Export.copyToPasteboard(Export.table(rows, system: settings.unitSystem))
        }
    }
}
