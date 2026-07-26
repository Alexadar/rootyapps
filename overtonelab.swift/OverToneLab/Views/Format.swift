import Foundation

enum Fmt {
    static let time: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    static func timeOrDash(_ d: Date?) -> String { d.map { time.string(from: $0) } ?? "—" }
    static func f(_ x: Double, _ places: Int = 2) -> String { String(format: "%.\(places)f", x) }
    static func signed(_ x: Double, _ places: Int = 2) -> String { String(format: "%+.\(places)f", x) }
    static func deg(_ x: Double, _ p: Int = 2) -> String { f(x, p) + "°" }
    static func pct(_ x: Double) -> String { String(format: "%.0f%%", x * 100) }
    static func secs(_ x: Double) -> String { x >= 10 ? f(x, 1) + " s" : f(x, 2) + " s" }
    static func hours(_ x: Double) -> String { f(x, 1) + " h" }
}
