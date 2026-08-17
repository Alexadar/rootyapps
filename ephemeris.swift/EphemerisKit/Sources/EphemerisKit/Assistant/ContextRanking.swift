import Foundation

/// How each surface decides which few rows survive truncation.
///
/// ## Ranking, never the first N
///
/// Taking the first four of a hundred and four is the obvious implementation and it is wrong in a
/// specific, predictable way: the user asks about the thing they are looking at, and the thing they
/// are looking at is almost never first. A timeline sorted by date opens thirty days in the past, so
/// head-truncation hands the model a month of history and drops today. An aspect list sorted by body
/// gives away Sun–Moon and hides the 0°06′ square that is the reason they asked.
///
/// So every surface names a rule, the rule is recorded in `Omission.ranking`, and the model is told
/// which rule was used. "Chosen by nearest to now" is information; "the first four" would be an
/// admission that nothing was chosen.
public enum ContextRanking {

    // MARK: - Time

    /// Nearest to `now`, in either direction.
    ///
    /// Both directions on purpose. A timeline's most useful rows are the last thing that happened
    /// and the next thing about to — "what just changed" is as common a question as "what is next",
    /// and a future-only rule answers only half of it.
    public static func nearest<T>(_ items: [T], to now: Date, limit: Int,
                                  date: (T) -> Date) -> [T] {
        items.sorted { abs(date($0).timeIntervalSince(now)) < abs(date($1).timeIntervalSince(now)) }
            .prefix(limit)
            .sorted { date($0) < date($1) }   // restore chronological order for reading
    }

    public static let nearestToNow = "nearest to now"

    // MARK: - Aspects

    /// Tightest orb first — the aspects a practitioner would actually comment on.
    public static func tightest(_ aspects: [DetectedAspect], limit: Int) -> [DetectedAspect] {
        aspects.sorted { abs($0.orb) < abs($1.orb) }.prefix(limit).map { $0 }
    }

    public static let tightestOrb = "tightest orb"

    // MARK: - Bodies

    /// The classical seven first, then the moderns.
    ///
    /// Not arbitrary: on a wheel the Sun, Moon and Ascendant are what anyone asks about first, and
    /// the outer planets move so slowly that their position is the least newsworthy thing on screen.
    public static func byProminence(_ positions: [BodyPosition], limit: Int) -> [BodyPosition] {
        let order = CelestialBody.allCases
        return positions
            .sorted { (order.firstIndex(of: $0.body) ?? 99) < (order.firstIndex(of: $1.body) ?? 99) }
            .prefix(limit)
            .map { $0 }
    }

    public static let classicalFirst = "the Sun, Moon and classical planets first"

    // MARK: - Distance

    public static let nearestToYou = "nearest to your location"

    // MARK: - Hours

    /// The current hour plus its neighbours, so "what is now and what is next" is always answerable.
    public static func aroundCurrent<T>(_ items: [T], currentIndex: Int?, limit: Int) -> [T] {
        guard !items.isEmpty else { return [] }
        guard let current = currentIndex else { return Array(items.prefix(limit)) }
        // One before, then forward — the previous hour explains what just ended.
        let start = Swift.max(0, current - 1)
        return Array(items[start...].prefix(limit))
    }

    public static let currentAndNext = "the current hour and the ones around it"
}
