import Foundation

/// Network plumbing + endpoint URLs. All sources are public / ToS-clean:
/// NOAA SWPC (services.swpc.noaa.gov) and GFZ Potsdam (kp.gfz.de).
enum API {
    static let swpc = "https://services.swpc.noaa.gov"
    static let gfz  = "https://kp.gfz.de"

    // NOAA SWPC
    static var kpForecast   = URL(string: "\(swpc)/products/noaa-planetary-k-index-forecast.json")!
    static var magSummary   = URL(string: "\(swpc)/products/summary/solar-wind-mag-field.json")!
    static var speedSummary = URL(string: "\(swpc)/products/summary/solar-wind-speed.json")!
    static var windRTSW     = URL(string: "\(swpc)/json/rtsw/rtsw_wind_1m.json")!
    static var xrays1Day    = URL(string: "\(swpc)/json/goes/primary/xrays-1-day.json")!
    static var flaresLatest = URL(string: "\(swpc)/json/goes/primary/xray-flares-latest.json")!
    /// Event LIST (begin/max/end per flare). `xray-flares-latest` carries only the most recent
    /// one, so a 24-hour tally needs this feed and a local time filter.
    static var flares7Day   = URL(string: "\(swpc)/json/goes/primary/xray-flares-7-day.json")!
    static var scales       = URL(string: "\(swpc)/products/noaa-scales.json")!
    static var ovation      = URL(string: "\(swpc)/json/ovation_aurora_latest.json")!
    static var f107         = URL(string: "\(swpc)/json/f107_cm_flux.json")!
    static var solarRegions = URL(string: "\(swpc)/json/solar_regions.json")!

    /// GFZ Hpo web service for the high-cadence index (Hp30 by default).
    static func gfzHpo(index: String = "Hp30", start: Date, end: Date) -> URL {
        var c = URLComponents(string: "\(gfz)/app/json/")!
        c.queryItems = [
            .init(name: "start", value: DateFmt.iso.string(from: start)),
            .init(name: "end", value: DateFmt.iso.string(from: end)),
            .init(name: "index", value: index),
            .init(name: "status", value: "def"),
        ]
        return c.url!
    }
}

public enum NetError: Error, Equatable {
    case http(Int)
}

enum Net {
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.waitsForConnectivity = false
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 30
        return URLSession(configuration: c)
    }()

    static func data(_ url: URL) async throws -> Data {
        // Per-REQUEST, not per-session: `session` is a `static let` and URLSessionConfiguration is
        // copied when the session is built, so the preference cannot be applied by mutating it.
        var request = URLRequest(url: url)
        request.allowsCellularAccess = SharedStore().cellularAllowed

        let (data, response) = try await session.data(for: request)
        // Without this an error page is not an error: a 5xx of HTML only failed later, at decode,
        // and read as "the feed returned nothing" rather than "the server is down".
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NetError.http(http.statusCode)
        }
        return data
    }

    static func json<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        try JSONDecoder().decode(T.self, from: await data(url))
    }
}

enum DateFmt {
    /// ISO-8601 with Z, for GFZ query params and 'Z'-suffixed feeds.
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let utc = TimeZone(identifier: "UTC")!
    private static func fixed(_ fmt: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = utc
        f.dateFormat = fmt
        return f
    }
    private static let candidates = [
        fixed("yyyy-MM-dd'T'HH:mm:ss"),
        fixed("yyyy-MM-dd HH:mm:ss.SSS"),
        fixed("yyyy-MM-dd HH:mm:ss"),
        fixed("yyyy-MM-dd'T'HH:mm"),
        fixed("yyyy-MM-dd"),
    ]

    /// Parse the many UTC timestamp shapes NOAA/GFZ emit; nil if none match.
    static func parseUTC(_ s: String) -> Date? {
        if let d = iso.date(from: s) { return d }
        for f in candidates { if let d = f.date(from: s) { return d } }
        return nil
    }
}
