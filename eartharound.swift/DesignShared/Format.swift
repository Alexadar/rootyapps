import SwiftUI

/// Value + data-age formatting. Staleness is shown honestly everywhere.
enum Fmt {
    private static let rel: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func age(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "no data" }
        return rel.localizedString(for: date, relativeTo: now)
    }

    /// True when the observation is older than `maxAge` (default 2 h) — flag it in the UI.
    static func isStale(_ date: Date?, maxAge: TimeInterval = 7200, now: Date = Date()) -> Bool {
        guard let date else { return true }
        return now.timeIntervalSince(date) > maxAge
    }

    static func num(_ v: Double?, _ decimals: Int = 1, dash: String = "—") -> String {
        guard let v else { return dash }
        return String(format: "%.\(decimals)f", v)
    }
    static func int(_ v: Int?, dash: String = "—") -> String { v.map(String.init) ?? dash }

    /// Scientific X-ray flux, e.g. 3.1e-6.
    static func flux(_ v: Double) -> String { String(format: "%.1e", v) }
}
