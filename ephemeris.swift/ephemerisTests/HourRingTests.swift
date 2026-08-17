import Testing
import Foundation
import EphemerisKit
@testable import Ephemeris

/// The planetary-hours ring geometry.
///
/// One property carries this whole surface: **the segments are unequal**. Twelve day hours divide
/// sunrise→sunset and twelve night hours divide sunset→sunrise, and away from the equinox those
/// intervals differ — in London in June a "day hour" runs about 82 minutes and a "night hour" about
/// 38. A ring of twenty-four equal wedges is not a simplification of that, it is a picture of a
/// different and wrong idea.
///
/// It is also the failure that is hardest to see by looking: an equal ring is perfectly tidy.
@Suite("Hour ring")
struct HourRingTests {

    private let london = GeoLocation(latitude: 51.5074, longitude: -0.1278)
    private let quito = GeoLocation(latitude: -0.18, longitude: -78.47)
    private var utc: TimeZone { TimeZone(secondsFromGMT: 0)! }

    private func noon(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = 12
        var cal = Calendar(identifier: .gregorian); cal.timeZone = utc
        return cal.date(from: c)!
    }

    private func angles(_ date: Date, _ loc: GeoLocation) -> [(start: Double, end: Double)] {
        guard let hours = PlanetaryHours.hours(startingOn: date, at: loc, timeZone: utc) else {
            Issue.record("no hours for \(date)"); return []
        }
        return HourRing.angles(for: hours)
    }

    // MARK: - The property the drawing exists to convey

    @Test func daySegmentsAndNightSegmentsHaveVisiblyDifferentWidths() {
        // Midsummer: the widest separation of the year at this latitude.
        let a = angles(noon(2026, 6, 21), london)
        #expect(a.count == 24)

        let widths = a.map { $0.end - $0.start }
        let day = Array(widths.prefix(12)), night = Array(widths.suffix(12))
        let dayMean = day.reduce(0, +) / 12
        let nightMean = night.reduce(0, +) / 12

        let ratio = dayMean / nightMean
        let why = "day hour \(String(format: "%.2f", dayMean))° vs night \(String(format: "%.2f", nightMean))° "
                + "— ratio \(String(format: "%.2f", ratio)); equal segments would be 15° each"
        #expect(ratio > 1.5, "\(why)")

        // And the difference must be large enough to actually see: several degrees of arc.
        #expect(abs(dayMean - nightMean) > 4, "\(why)")
    }

    /// Within a half, the twelve are equal — the unequalness is between day and night, not noise.
    @Test func theTwelveHoursWithinEachHalfAreEqualToEachOther() {
        let a = angles(noon(2026, 6, 21), london)
        let widths = a.map { $0.end - $0.start }
        for half in [Array(widths.prefix(12)), Array(widths.suffix(12))] {
            let spread = (half.max() ?? 0) - (half.min() ?? 0)
            #expect(spread < 0.01, "hours within one half should be equal, spread \(spread)°")
        }
    }

    /// At the equator the two halves are nearly equal — so the test above is measuring latitude,
    /// not an artefact of the drawing.
    @Test func atTheEquatorTheHalvesAreNearlyEqual() {
        let widths = angles(noon(2026, 6, 21), quito).map { $0.end - $0.start }
        guard widths.count == 24 else { return }
        let dayMean = widths.prefix(12).reduce(0, +) / 12
        let nightMean = widths.suffix(12).reduce(0, +) / 12
        #expect(abs(dayMean - nightMean) < 1.5,
                "equator halves should be close: \(dayMean)° vs \(nightMean)°")
    }

    // MARK: - Ring integrity

    @Test func segmentsTileTheCircleWithoutGapOrOverlap() {
        for date in [noon(2026, 3, 20), noon(2026, 6, 21), noon(2026, 12, 21)] {
            let a = angles(date, london)
            guard !a.isEmpty else { continue }
            for (x, y) in zip(a, a.dropFirst()) {
                #expect(abs(y.start - x.end) < 1e-6, "gap between segments at \(date)")
            }
            let total = a.last!.end - a.first!.start
            #expect(abs(total - 360) < 1e-6, "ring spans \(total)°, not 360")
            #expect(abs(a.first!.start + 90) < 1e-6, "the ring should open at the top")
        }
    }

    @Test func everySegmentAdvancesClockwise() {
        for (i, seg) in angles(noon(2026, 12, 21), london).enumerated() {
            #expect(seg.end > seg.start, "segment \(i) runs backwards")
        }
    }

    /// Degenerate input must produce no ring rather than a divide-by-zero or a NaN sweep.
    @Test func emptyInputProducesNoSegments() {
        #expect(HourRing.angles(for: []).isEmpty)
    }

    // MARK: - Polar honesty

    /// Above the Arctic Circle in midsummer there is no sunrise, so there is no interval to divide.
    /// The Kit returns nil and the view shows a written explanation — neither invents an hour.
    @Test func polarMidsummerHasNoHoursAtAll() {
        let longyearbyen = GeoLocation(latitude: 78.22, longitude: 15.63)
        let hours = PlanetaryHours.hours(startingOn: noon(2026, 6, 21), at: longyearbyen, timeZone: utc)
        #expect(hours == nil, "expected no planetary hours during polar day")
    }

    // MARK: - Which absence

    /// "No hours" has two causes and only one of them is the sky.
    ///
    /// Framing Los Angeles in Kyiv's civil day yields a real sunrise at 16:16 and a real sunset at
    /// 05:37 — different solar days, so no interval. Telling that user "no sunrise today" is false
    /// and unfixable-looking; naming the time zone is true and actionable. Caught by reading a UI
    /// test's accessibility dump, which showed "No sunrise today" for Los Angeles.
    @Test func aZoneMismatchIsNotReportedAsAPolarNight() {
        let la = GeoLocation(latitude: 34.05, longitude: -118.24, name: "Los Angeles")
        let day = noon(2026, 8, 18)

        // Its own zone: hours exist, so no reason is needed.
        #expect(PlanetaryHours.hours(startingOn: day, at: la,
                                     timeZone: TimeZone(identifier: "America/Los_Angeles")!) != nil)

        // A distant zone: no hours, and the cause is the zone — not the sky.
        for zone in ["Europe/Kyiv", "Asia/Tokyo", "UTC"] {
            let tz = TimeZone(identifier: zone)!
            #expect(PlanetaryHours.hours(startingOn: day, at: la, timeZone: tz) == nil,
                    "\(zone) should not frame LA's day")
            #expect(HoursUnavailable.reason(at: la, on: day, timeZone: tz) == .zoneMismatch,
                    "\(zone) must report a zone mismatch, not a polar night")
        }
    }

    /// And a genuine polar day still reports as polar, so the new branch has not swallowed the old.
    @Test func aPolarDayStillReportsAsPolar() {
        let longyearbyen = GeoLocation(latitude: 78.22, longitude: 15.63)
        let midsummer = noon(2026, 6, 21)
        #expect(PlanetaryHours.hours(startingOn: midsummer, at: longyearbyen, timeZone: utc) == nil)
        #expect(HoursUnavailable.reason(at: longyearbyen, on: midsummer, timeZone: utc) == .polar)
    }
}
