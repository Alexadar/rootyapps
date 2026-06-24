import Foundation

/// Serializes an `AstroEvent` timeline (and the `EventCatalog` legend) to CSV and JSON
/// for an external indicator. CLI-independent and fully testable.
public enum TimelineExporter {
    public static let version = "1.0"

    /// One indicator-friendly row per event.
    public struct Record: Codable, Hashable {
        public let date_utc: String
        public let timestamp_unix: Int
        public let code: Int
        public let event_class: String
        public let kind: String
        public let body_a: String
        public let body_b: String
        public let aspect: String
        public let longitude_a: Double
        public let longitude_b: Double?
        public let sign: String
        public let retro_a: Bool
        public let retro_b: Bool
        public let label: String
    }

    public struct Document: Codable {
        public let generated_for_range: [String]   // [fromISO, toISO]
        public let version: String
        public let events: [Record]
    }

    public static let csvHeader =
        "date_utc,timestamp_unix,code,event_class,kind,body_a,body_b,aspect,longitude_a,longitude_b,sign,retro_a,retro_b,label"

    // MARK: Records

    public static func records(_ events: [AstroEvent]) -> [Record] {
        events.sorted { $0.date < $1.date }.map { e in
            Record(date_utc: iso(e.date),
                   timestamp_unix: Int(e.date.timeIntervalSince1970),
                   code: e.code,
                   event_class: e.eventClass.rawValue,
                   kind: e.kind.rawValue,
                   body_a: e.bodyA.rawValue,
                   body_b: e.bodyB?.rawValue ?? "",
                   aspect: e.aspect?.name ?? "",
                   longitude_a: round3(e.longitudeA),
                   longitude_b: e.longitudeB.map(round3),
                   sign: e.sign?.name ?? "",
                   retro_a: e.retroA,
                   retro_b: e.retroB,
                   label: e.label())
        }
    }

    // MARK: CSV / JSON (events)

    public static func csv(_ events: [AstroEvent]) -> String {
        var lines = [csvHeader]
        for r in records(events) {
            lines.append([
                r.date_utc, String(r.timestamp_unix), String(r.code), r.event_class, r.kind,
                r.body_a, r.body_b, r.aspect, num(r.longitude_a), r.longitude_b.map(num) ?? "",
                r.sign, String(r.retro_a), String(r.retro_b), r.label
            ].map(csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func json(_ events: [AstroEvent], range: DateInterval) -> Data {
        let doc = Document(generated_for_range: [iso(range.start), iso(range.end)],
                           version: version, events: records(events))
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? enc.encode(doc)) ?? Data()
    }

    // MARK: Legend (the exposed code→meaning dictionary)

    public static func legendCSV() -> String {
        var lines = ["code,key,label"]
        for e in EventCatalog.entries {
            lines.append([String(e.code), e.key, e.label].map(csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func legendJSON() -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? enc.encode(EventCatalog.entries)) ?? Data()
    }

    // MARK: Helpers

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
    private static func iso(_ d: Date) -> String { isoFormatter.string(from: d) }
    private static func round3(_ x: Double) -> Double { (x * 1000).rounded() / 1000 }
    private static func num(_ x: Double) -> String { String(format: "%.3f", x) }
    private static func csvField(_ s: String) -> String {
        (s.contains(",") || s.contains("\"") || s.contains("\n"))
            ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            : s
    }
}
