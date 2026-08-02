import Foundation

/// Which upstream feed a panel came from. The app shows seven panels but they do not refresh
/// alike: NOAA republishes the scales every minute and F10.7 three times a day, so "updated 3m
/// ago" beside "updated 4h ago" is usually the truth rather than a bug. What the app could not
/// say until now is whether a panel is old because the SOURCE is slow or because OUR FETCH
/// failed — `FeedStatus` is that missing distinction.
public enum FeedSource: String, CaseIterable, Codable, Sendable {
    case kp, flares, wind, scales, aurora, solar, hpo

    /// How often the publisher actually issues a new observation. Staleness has to be judged
    /// against this: a flat threshold marks F10.7 stale permanently and Hp30 never.
    /// Sources: NOAA SWPC product cadences; GFZ Hpo is a 30-minute index.
    public var expectedCadence: TimeInterval {
        switch self {
        case .scales, .flares, .wind: return 60 * 5      // minute-cadence feeds
        case .aurora:                 return 60 * 10     // OVATION ~5 min
        case .hpo:                    return 60 * 30     // GFZ Hp30, published ~35 min behind
        case .kp:                     return 60 * 60 * 3 // 3-hourly Bartels interval
        case .solar:                  return 60 * 60 * 8 // F10.7 issued 3x/day
        }
    }

    /// Tolerate two missed publications before calling a source stale.
    public var staleAfter: TimeInterval { expectedCadence * 2.5 }
}

/// What happened on the last attempt. `empty` is separate from `failed` on purpose: a 200 that
/// decodes to nothing (GFZ returning no readings, NOAA scales missing the "0" key) used to
/// overwrite good data and still report success.
public enum FetchOutcome: String, Codable, Sendable {
    case ok, empty, failed, skippedOffline, skippedCellular

    public var isFailure: Bool { self != .ok }
}

public struct SourceStatus: Codable, Equatable, Sendable {
    public var lastAttempt: Date?
    public var lastSuccess: Date?
    public var outcome: FetchOutcome

    public init(lastAttempt: Date? = nil, lastSuccess: Date? = nil, outcome: FetchOutcome = .ok) {
        self.lastAttempt = lastAttempt
        self.lastSuccess = lastSuccess
        self.outcome = outcome
    }
}

/// Per-source fetch record, persisted in the app group so a partial fetch by one process (the
/// widget only fetches five of the seven) is visible to the others.
public struct FeedStatus: Codable, Equatable, Sendable {
    public var sources: [FeedSource: SourceStatus]

    public init(sources: [FeedSource: SourceStatus] = [:]) { self.sources = sources }

    public subscript(source: FeedSource) -> SourceStatus {
        get { sources[source] ?? SourceStatus() }
        set { sources[source] = newValue }
    }

    public mutating func record(_ source: FeedSource, _ outcome: FetchOutcome, at date: Date) {
        var s = self[source]
        s.lastAttempt = date
        s.outcome = outcome
        if outcome == .ok { s.lastSuccess = date }
        self[source] = s
    }

    /// Merge another process's record in without losing a fresher success of our own.
    public mutating func merge(_ other: FeedStatus) {
        for (source, theirs) in other.sources {
            let mine = self[source]
            guard let mineSuccess = mine.lastSuccess, let theirSuccess = theirs.lastSuccess else {
                if mine.lastAttempt == nil || (theirs.lastAttempt ?? .distantPast) > (mine.lastAttempt ?? .distantPast) {
                    self[source] = theirs
                }
                continue
            }
            if theirSuccess >= mineSuccess { self[source] = theirs }
        }
    }

    /// True when this source's own last attempt did not succeed — the "couldn't refresh" case,
    /// as opposed to a source that simply publishes slowly.
    public func didFail(_ source: FeedSource) -> Bool { self[source].outcome.isFailure }

    /// Stale against the source's own cadence, not a single global threshold.
    public func isStale(_ source: FeedSource, now: Date = Date()) -> Bool {
        guard let success = self[source].lastSuccess else { return true }
        return now.timeIntervalSince(success) > source.staleAfter
    }

    public var anyFailed: Bool { FeedSource.allCases.contains { didFail($0) } }
    public var allFailed: Bool { FeedSource.allCases.allSatisfy { didFail($0) } }
}
