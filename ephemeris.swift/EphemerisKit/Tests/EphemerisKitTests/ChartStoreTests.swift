import Testing
import Foundation
@testable import EphemerisKit

/// The store is where a user's own data lives, so it is tested against the ways stores actually
/// fail — not just the happy path.
///
/// Every competing app's loudest review is some form of "my saved charts disappeared". The failures
/// below are the mechanisms behind that sentence: a truncated write, a record dropped by an older
/// client, a single corrupt file taking the library with it, a delete that comes back.
@Suite("Chart store")
struct ChartStoreTests {

    private func tempRoot() throws -> URL {
        let u = FileManager.default.temporaryDirectory
            .appendingPathComponent("charts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private func sample(name: String = "Test") -> SavedChart {
        SavedChart(name: name,
                   birthInstant: ISO8601DateFormatter().date(from: "1990-03-15T14:30:00Z")!,
                   timeZoneID: "Europe/Berlin",
                   latitude: 52.52, longitude: 13.405, placeName: "Berlin")
    }

    // MARK: - Round trip

    @Test func savedChartSurvivesARoundTrip() throws {
        let root = try tempRoot()
        let store = try ICloudChartStore(localRoot: root)
        let chart = sample(name: "Anna")
        try store.save(chart)

        let back = try #require(try store.chart(id: chart.id))
        #expect(back.name == "Anna")
        #expect(back.timeZoneID == "Europe/Berlin")
        #expect(back.birthInstant == chart.birthInstant)
        #expect(back.latitude == 52.52)
    }

    @Test func eachChartIsItsOwnFile() throws {
        let root = try tempRoot()
        let store = try ICloudChartStore(localRoot: root)
        try store.save(sample(name: "A"))
        try store.save(sample(name: "B"))

        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        #expect(files.count == 2, "one file per chart — this is what keeps sync conflicts scoped")
    }

    // MARK: - The forward-compatibility property

    /// ⚠ THE DATA-LOSS CASE. An older app version must not silently delete a newer version's fields.
    ///
    /// Simulated by writing a record containing a key this version has never heard of, loading it,
    /// editing something ordinary, saving, and checking the unknown key is still there. Without the
    /// preservation logic this test fails and a real user quietly loses data during sync.
    @Test func unknownFieldsFromANewerVersionSurviveAnEditByThisVersion() throws {
        let root = try tempRoot()
        let store = try ICloudChartStore(localRoot: root)
        let chart = sample(name: "Original")
        try store.save(chart)

        // Hand-write a "version 2" field into the file on disk.
        let file = root.appendingPathComponent("\(chart.id.uuidString).json")
        var raw = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        raw["rectifiedTime"] = "1990-03-15T14:32:00Z"
        raw["confidence"] = 0.87
        try JSONSerialization.data(withJSONObject: raw).write(to: file)

        // This version loads it, renames it, saves it back.
        var loaded = try #require(try store.chart(id: chart.id))
        #expect(loaded.unknownKeys["rectifiedTime"] != nil, "unknown keys must be captured on read")
        loaded.name = "Renamed by an older client"
        try store.save(loaded)

        let after = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        #expect(after["name"] as? String == "Renamed by an older client")
        #expect(after["rectifiedTime"] as? String == "1990-03-15T14:32:00Z",
                "THE BUG: a field this version does not understand was destroyed by a round trip")
        #expect(after["confidence"] as? Double == 0.87)
    }

    @Test func schemaVersionIsWritten() throws {
        let root = try tempRoot()
        let store = try ICloudChartStore(localRoot: root)
        let chart = sample()
        try store.save(chart)
        let raw = try JSONSerialization.jsonObject(
            with: Data(contentsOf: root.appendingPathComponent("\(chart.id.uuidString).json"))
        ) as! [String: Any]
        #expect(raw["schemaVersion"] as? Int == SavedChart.currentSchemaVersion,
                "a migration later needs something to branch on")
    }

    // MARK: - Deletion

    @Test func deleteTombstonesRatherThanErasing() throws {
        let root = try tempRoot()
        let store = try ICloudChartStore(localRoot: root)
        let chart = sample()
        try store.save(chart)
        try store.delete(id: chart.id)

        #expect(try store.all().isEmpty, "a deleted chart is not in the library")
        #expect(try store.allIncludingDeleted().count == 1,
                "but the record survives, or a device that was offline resurrects it on next sync")
        #expect(try store.chart(id: chart.id)?.deletedAt != nil)
    }

    // MARK: - Resilience

    @Test func oneCorruptFileDoesNotTakeTheLibraryDown() throws {
        let root = try tempRoot()
        let store = try ICloudChartStore(localRoot: root)
        let good = sample(name: "Readable")
        try store.save(good)
        try Data("{ this is not json".utf8)
            .write(to: root.appendingPathComponent("\(UUID().uuidString).json"))

        let all = try store.all()
        #expect(all.count == 1, "the readable chart must still load")
        #expect(all.first?.name == "Readable")
    }

    /// Requirement: subfolders later, with no migration. Proven now by putting a record in a
    /// subdirectory and expecting the store to find it, long before any UI can create one.
    @Test func enumerationIsRecursiveSoSubfoldersNeedNoMigration() throws {
        let root = try tempRoot()
        let store = try ICloudChartStore(localRoot: root)
        let nested = root.appendingPathComponent("Clients", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let chart = sample(name: "In a subfolder")
        let data = try JSONEncoder.iso8601Pretty.encode(chart)
        try data.write(to: nested.appendingPathComponent("\(chart.id.uuidString).json"))

        let all = try store.all()
        #expect(all.contains { $0.name == "In a subfolder" },
                "a chart inside a folder must be found today, or folders become a migration later")
    }

    @Test func untimedChartsHaveNoHouses() throws {
        var chart = sample()
        chart.isTimeKnown = false
        #expect(chart.houses(system: .placidus) == nil,
                "houses must be absent rather than computed from an assumed noon")
        #expect(!chart.positions.isEmpty, "positions remain valid without a birth time")
    }
}

private extension JSONEncoder {
    static var iso8601Pretty: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}
