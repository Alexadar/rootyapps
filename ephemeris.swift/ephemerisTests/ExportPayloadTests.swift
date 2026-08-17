import Testing
import Foundation
import EphemerisKit
@testable import Ephemeris

/// Export.
///
/// The property worth asserting is that **the summary the sheet shows and the bytes the user gets
/// come from the same place**. A count computed from one array and a file written from another is
/// the failure that cannot be seen: neither the number nor the file looks wrong on its own, and the
/// user only finds out when a colleague opens it.
@Suite("Export payload")
struct ExportPayloadTests {

    private func window() -> DateInterval {
        let start = utc(2026, 1, 1)
        return DateInterval(start: start, end: start.addingTimeInterval(90 * 86_400))
    }

    private func events() -> [AstroEvent] {
        EventTimeline.allEvents(in: window())
    }

    private func payload() -> ExportPayload {
        ExportPayload(subject: .events("ephemeris-timeline"),
                      content: .events(events()), range: window())
    }

    // MARK: - The summary is the file

    @Test func theStatedCountMatchesTheRowsInTheFile() {
        let p = payload()
        #expect(p.count > 0, "the window should contain events")

        let csv = String(decoding: p.data(.csv), as: UTF8.self)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true)
        // One header plus one row per event.
        #expect(lines.count == p.count + 1,
                "stated \(p.count) events, CSV holds \(lines.count - 1) rows")
    }

    @Test func theStatedRangeIsTheRangeInTheJSON() throws {
        let p = payload()
        let obj = try #require(try JSONSerialization.jsonObject(with: p.data(.json)) as? [String: Any])
        let range = try #require(obj["generated_for_range"] as? [String])
        #expect(range.count == 2)

        let iso = ISO8601DateFormatter()
        let from = try #require(iso.date(from: range[0]))
        #expect(abs(from.timeIntervalSince(p.range.start)) < 1,
                "JSON range starts \(range[0]), payload says \(p.range.start)")
    }

    @Test func everyEventReachesTheJSON() throws {
        let p = payload()
        let obj = try #require(try JSONSerialization.jsonObject(with: p.data(.json)) as? [String: Any])
        let records = try #require(obj["events"] as? [[String: Any]] ?? obj["records"] as? [[String: Any]])
        #expect(records.count == p.count, "JSON holds \(records.count) of \(p.count) events")
    }

    // MARK: - Empty is stated, not hidden

    @Test func anEmptyWindowIsEmptyRatherThanFabricated() {
        // A one-second window in the far future contains nothing.
        let tiny = DateInterval(start: utc(2090, 1, 1), duration: 1)
        let p = ExportPayload(subject: .events("empty"), content: .events([]), range: tiny)
        #expect(p.isEmpty)
        #expect(p.count == 0)
        let csv = String(decoding: p.data(.csv), as: UTF8.self)
        // A header and nothing else — the sheet warns about exactly this.
        let rows = csv.split(separator: "\n").dropFirst()
        #expect(rows.isEmpty, "empty export produced \(rows.count) rows")
    }

    // MARK: - Charts export their own document

    @Test func aChartExportsTheDocumentICloudStores() throws {
        let chart = SavedChart(name: "Ada Lovelace",
                               birthInstant: utc(1815, 12, 10, 13, 0),
                               timeZoneID: "Europe/London",
                               isTimeKnown: true,
                               latitude: 51.5074, longitude: -0.1278, placeName: "London")
        let p = ExportPayload(subject: .chart(chart.name), content: .chart(chart),
                              range: DateInterval(start: chart.birthInstant, duration: 1))

        #expect(p.count == 1, "a chart is one document, not a row count")
        #expect(p.availableFormats == [.json], "a chart has no meaningful CSV form")

        // It must decode back to the same chart — this is the file iCloud syncs.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let round = try decoder.decode(SavedChart.self, from: p.data(.json))
        #expect(round.id == chart.id)
        #expect(round.name == chart.name)
        #expect(abs(round.birthInstant.timeIntervalSince(chart.birthInstant)) < 1)
        #expect(round.timeZoneID == chart.timeZoneID)
    }

    // MARK: - File names

    /// A chart named "Mum / Dad: 2" must not produce a path separator or a colon — one writes a
    /// nested directory, the other fails silently on some filesystems.
    @Test func fileNamesAreFilesystemSafe() {
        let nasty = ExportPayload(subject: .chart("Mum / Dad: 2 ★"),
                                  content: .events([]), range: window())
        let name = nasty.fileName(.json)
        #expect(!name.contains("/"), "\(name) contains a path separator")
        #expect(!name.contains(":"), "\(name) contains a colon")
        #expect(name.hasSuffix(".json"))
        #expect(name.count > 5, "\(name) collapsed to nothing")
    }

    @Test func anAllPunctuationNameStillProducesAFile() {
        let p = ExportPayload(subject: .chart("///"), content: .events([]), range: window())
        #expect(p.fileName(.csv) == "ephemeris.csv", "got \(p.fileName(.csv))")
    }

    @Test func eachSubjectCarriesItsOwnIdentifier() {
        #expect(ExportPayload.Subject.events("x").identifier == "export.events")
        #expect(ExportPayload.Subject.chart("x").identifier == "export.chart")
        #expect(ExportPayload.Subject.moon("x").identifier == "export.moon")
    }

    // MARK: - Writing

    @Test func writingProducesAReadableFileWithTheSameBytes() throws {
        let p = payload()
        let url = try p.writeTemporary(.csv)
        defer { try? FileManager.default.removeItem(at: url) }

        let onDisk = try Data(contentsOf: url)
        #expect(onDisk == p.data(.csv), "the written file differs from the previewed data")
        #expect(url.lastPathComponent == p.fileName(.csv))
    }

    /// The legend is what makes the CSV's `code` column readable. Exporting rows without it hands
    /// someone a spreadsheet of integers.
    @Test func theLegendIsAvailableAndNonEmpty() {
        let p = payload()
        #expect(p.legend(.csv).count > 50)
        #expect(p.legend(.json).count > 50)
    }
}
