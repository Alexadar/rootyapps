import WidgetKit
import SwiftUI
import EphemerisKit

/// The Ascendant — the rising sign — as a complication.
///
/// This is the one value in the whole app that earns a place on a watch face. Planetary positions
/// move over days and weeks; the Ascendant crosses a sign boundary roughly every two hours, so it
/// is genuinely different each time you look. It is also the reason a real ephemeris matters here:
/// it is a function of sidereal time *and the observer's place*, so nothing that only knows the
/// date can produce it.
///
/// No background refresh is involved and none is possible. WidgetKit renders from a timeline
/// supplied ahead of time, with this process not running. Because the engine is deterministic and
/// costs microseconds, the timeline is not a series of guesses on a polling interval — every entry
/// is stamped with the *exact instant* the sign changes, computed by bisection below.
struct RisingSignEntry: TimelineEntry {
    let date: Date
    /// Nil when no place has been set. The Ascendant cannot be faked from the date alone, and a
    /// guessed location yields a confidently wrong answer, so the view must show an empty state.
    let sign: ZodiacSign?
    let degreesIntoSign: Double
    let placeName: String?
}

struct RisingSignProvider: TimelineProvider {
    func placeholder(in context: Context) -> RisingSignEntry {
        RisingSignEntry(date: .now, sign: .aries, degreesIntoSign: 12, placeName: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (RisingSignEntry) -> Void) {
        completion(Self.entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RisingSignEntry>) -> Void) {
        var entries = [Self.entry(at: .now)]
        var cursor = Date.now
        // One entry per sign boundary for the next 24h — twelve-ish, comfortably inside WidgetKit's
        // budget, and it buys a whole day of exactly-correct values for a single reload.
        for _ in 0..<14 {
            guard let next = Self.nextSignChange(after: cursor) else { break }
            entries.append(Self.entry(at: next))
            cursor = next.addingTimeInterval(1)
            if cursor.timeIntervalSinceNow > 86_400 { break }
        }
        completion(Timeline(entries: entries, policy: .after(cursor)))
    }

    // MARK: computation

    static func ascendant(at date: Date) -> (sign: ZodiacSign, into: Double)? {
        guard let location = SharedStore().location,
              let houses = Houses.compute(at: date, location: location,
                                          system: SharedStore().houseSystem)
        else { return nil }
        let lon = AstroMath.norm360(houses.angles.ascendant)
        return (ZodiacSign.from(longitude: lon), lon.truncatingRemainder(dividingBy: 30))
    }

    static func entry(at date: Date) -> RisingSignEntry {
        let a = ascendant(at: date)
        return RisingSignEntry(date: date, sign: a?.sign, degreesIntoSign: a?.into ?? 0,
                               placeName: SharedStore().location?.name)
    }

    /// The instant the Ascendant next enters a new sign, found by bisection.
    ///
    /// Stepping in fixed minutes would be both slower and wrong — the Ascendant's rate varies
    /// enormously with latitude (signs of long and short ascension), so a boundary can be missed
    /// entirely near the poles. Bracket first, then bisect to the second.
    static func nextSignChange(after start: Date) -> Date? {
        guard let s0 = ascendant(at: start)?.sign else { return nil }
        var lo = start
        var hi: Date?
        var probe = start
        for _ in 0..<(6 * 24) {                      // scan up to 24h in 10-minute brackets
            probe = probe.addingTimeInterval(600)
            guard let s = ascendant(at: probe)?.sign else { return nil }
            if s != s0 { hi = probe; break }
            lo = probe
        }
        guard var high = hi else { return nil }
        for _ in 0..<40 {                            // bisect to sub-second
            let mid = Date(timeIntervalSince1970: (lo.timeIntervalSince1970 + high.timeIntervalSince1970) / 2)
            guard let s = ascendant(at: mid)?.sign else { return nil }
            if s == s0 { lo = mid } else { high = mid }
        }
        return high
    }
}
