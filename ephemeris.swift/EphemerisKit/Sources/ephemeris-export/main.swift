import Foundation
import EphemerisKit

// MARK: - Tiny arg parser

func parseArgs(_ argv: [String]) -> [String: String] {
    var out: [String: String] = [:]
    var i = 0
    while i < argv.count {
        let a = argv[i]
        if a.hasPrefix("--") {
            let key = String(a.dropFirst(2))
            if i + 1 < argv.count, !argv[i + 1].hasPrefix("--") {
                out[key] = argv[i + 1]; i += 2
            } else {
                out[key] = "true"; i += 1   // flag
            }
        } else { i += 1 }
    }
    return out
}

func die(_ msg: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + msg + "\n").utf8))
    exit(1)
}

func warn(_ msg: String) {
    FileHandle.standardError.write(Data(("warning: " + msg + "\n").utf8))
}

func parseDate(_ s: String) -> Date {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd"
    guard let d = f.date(from: s) else { die("bad date '\(s)', expected yyyy-MM-dd") }
    return d
}

func write(_ text: String, to path: String?) {
    if let path { try? text.write(toFile: path, atomically: true, encoding: .utf8) }
    else { FileHandle.standardOutput.write(Data(text.utf8)) }
}

// MARK: - Main

let args = parseArgs(Array(CommandLine.arguments.dropFirst()))

// --dump-legend: just emit the full code→meaning dictionary and exit.
if args["dump-legend"] != nil {
    let fmt = args["format"] ?? "csv"
    let text = fmt == "json" ? String(decoding: TimelineExporter.legendJSON(), as: UTF8.self)
                             : TimelineExporter.legendCSV()
    write(text, to: args["out"])
    exit(0)
}

guard let fromStr = args["from"], let toStr = args["to"] else {
    die("--from and --to are required (or use --dump-legend)")
}
let from = parseDate(fromStr), to = parseDate(toStr)
guard to > from else { die("--to must be after --from") }

// Pluto series validity ~1800–2099.
let cal = Calendar(identifier: .gregorian)
let y0 = cal.component(.year, from: from), y1 = cal.component(.year, from: to)
if y0 < 1800 || y1 > 2099 { warn("range \(y0)–\(y1) outside Pluto validity ~1800–2099; positions may degrade") }

let bodies: [CelestialBody] = {
    let v = args["bodies"] ?? "all"
    if v == "all" { return CelestialBody.allCases }
    return v.split(separator: ",").compactMap { CelestialBody(rawValue: String($0)) }
}()

let include: Set<EventClass> = {
    let v = args["events"] ?? "all"
    if v == "all" { return Set(EventClass.allCases) }
    var set = Set<EventClass>()
    for tok in v.split(separator: ",") {
        switch tok {
        case "ingress": set.insert(.ingress)
        case "lunation": set.insert(.lunation)
        case "station": set.insert(.station)
        case "conjunction": set.insert(.conjunction)
        case "opposition": set.insert(.opposition)
        case "elongation": set.insert(.elongation)
        case "aspect": set.insert(.aspect)
        default: warn("unknown event class '\(tok)' ignored")
        }
    }
    return set
}()

let interval = DateInterval(start: from, end: to)
let events = EventTimeline.allEvents(in: interval, bodies: bodies, include: include)

let format = args["format"] ?? "csv"
switch format {
case "csv":  write(TimelineExporter.csv(events), to: args["out"])
case "json": write(String(decoding: TimelineExporter.json(events, range: interval), as: UTF8.self), to: args["out"])
default: die("unknown --format '\(format)' (use csv or json)")
}

// Optional separate legend file.
if let legendPath = args["legend"] {
    let isJSON = legendPath.hasSuffix(".json")
    let text = isJSON ? String(decoding: TimelineExporter.legendJSON(), as: UTF8.self)
                      : TimelineExporter.legendCSV()
    write(text, to: legendPath)
}

FileHandle.standardError.write(Data("wrote \(events.count) events\n".utf8))
