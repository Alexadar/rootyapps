import Testing
import Foundation
import EphemerisKit

@Suite("Timeline exporter")
struct ExporterTests {
    let range = DateInterval(start: utc(2026, 1, 1), end: utc(2026, 6, 30))
    var events: [AstroEvent] { EventTimeline.allEvents(in: range) }

    @Test func csvRowCountAndSorting() {
        let evs = events
        let csv = TimelineExporter.csv(evs)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == evs.count + 1)          // header + one row per event
        #expect(lines.first.map(String.init) == TimelineExporter.csvHeader)

        let recs = TimelineExporter.records(evs)
        for i in 1..<recs.count { #expect(recs[i - 1].timestamp_unix <= recs[i].timestamp_unix) }
    }

    @Test func jsonRoundTrips() throws {
        let data = TimelineExporter.json(events, range: range)
        let doc = try JSONDecoder().decode(TimelineExporter.Document.self, from: data)
        #expect(doc.version == TimelineExporter.version)
        #expect(doc.events.count == events.count)
        #expect(doc.generated_for_range.count == 2)
        #expect(doc.events.allSatisfy { $0.code >= 0 })
    }

    @Test func legendMatchesCatalog() throws {
        let csvLines = TimelineExporter.legendCSV().split(separator: "\n", omittingEmptySubsequences: true)
        #expect(csvLines.count == EventCatalog.entries.count + 1)   // header + entries

        let entries = try JSONDecoder().decode([EventCatalog.Entry].self, from: TimelineExporter.legendJSON())
        #expect(entries.count == EventCatalog.entries.count)
        #expect(entries.map { $0.code } == EventCatalog.entries.map { $0.code })
    }
}
