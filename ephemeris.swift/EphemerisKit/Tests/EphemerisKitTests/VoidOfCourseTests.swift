import Testing
import Foundation
@testable import EphemerisKit

/// The void-of-course Moon.
///
/// The published rows are the weakest part of this suite, not the strongest — the source does not
/// state which bodies it counts, so it cannot arbitrate the one genuinely contested part of the
/// definition. The identities carry the weight here, and the strongest of them is
/// `noExactAspectFallsInsideAVoidPeriod`: it is the definition restated as something a wrong search
/// cannot satisfy.
@Suite("Void of course")
struct VoidOfCourseTests {

    private let zone = TimeZone(secondsFromGMT: 0)!

    private func near(_ target: Double, _ dates: [Date]) -> TimeInterval? {
        dates.map { $0.timeIntervalSince1970 - target }.min { abs($0) < abs($1) }
    }

    // MARK: - Against the published table

    @Test func periodsMatchThePublishedTable() {
        let o = Oracles.require("voc-moontracks-periods")
        let window = DateInterval(start: utc(2026, 9, 27), end: utc(2026, 10, 1))
        let periods = VoidOfCourse.periods(in: window)

        for (key, expected) in o.values.sorted(by: { $0.key < $1.key }) {
            let dates = key.hasSuffix("start") ? periods.map(\.start) : periods.map(\.end)
            guard let err = near(expected, dates) else {
                Issue.record("no period near \(key)"); continue
            }
            let detail = "\(key): off by \(String(format: "%.1f", err / 60)) min"
            #expect(o.matches(key, expected + err), "\(detail)")
        }
    }

    /// The table names the aspecting body and the aspect. Reproducing those is a stronger statement
    /// than reproducing the time: a search that found the wrong aspect at nearly the right moment
    /// would pass on timing alone.
    @Test func theLastAspectMatchesTheOneThePublishedTableNames() {
        let window = DateInterval(start: utc(2026, 9, 27), end: utc(2026, 10, 1))
        let periods = VoidOfCourse.periods(in: window)

        guard let aries = periods.first(where: { $0.sign == .aries }),
              let taurus = periods.first(where: { $0.sign == .taurus })
        else { Issue.record("expected voids in Aries and Taurus"); return }

        let whyA = "table says Moon opp Mercury, got \(aries.lastBody?.name ?? "-") "
                 + "\(aries.lastAspect?.name ?? "-")"
        #expect(aries.lastBody == .mercury && aries.lastAspect?.name == "Opposition", "\(whyA)")

        let whyT = "table says Moon sqr Jupiter, got \(taurus.lastBody?.name ?? "-") "
                 + "\(taurus.lastAspect?.name ?? "-")"
        #expect(taurus.lastBody == .jupiter && taurus.lastAspect?.name == "Square", "\(whyT)")
    }

    // MARK: - The definition, as identities

    /// **The definition restated.** If any exact aspect falls strictly inside a void period, the
    /// period started too early — the whole claim is that there are none left.
    @Test func noExactAspectFallsInsideAVoidPeriod() {
        let window = DateInterval(start: utc(2026, 1, 1), end: utc(2026, 3, 1))
        let periods = VoidOfCourse.periods(in: window)
        #expect(periods.count > 20, "two months should hold ~25 periods, found \(periods.count)")

        for p in periods {
            let intruder = VoidOfCourse.lastExactAspect(from: p.start, to: p.end,
                                                        bodies: VoidOfCourse.traditional)
            if let intruder {
                let mins = intruder.date.timeIntervalSince(p.start) / 60
                let why = "void from \(p.start) holds a \(intruder.aspect.name) to "
                        + "\(intruder.body.name) \(Int(mins)) min in"
                Issue.record("\(why)")
            }
            #expect(intruder == nil)
        }
    }

    /// A void ends at a sign boundary — that is what ends it. So the Moon must be in the period's
    /// sign just before `end` and in a different one just after.
    @Test func everyPeriodEndsExactlyAtASignIngress() {
        for p in VoidOfCourse.periods(in: DateInterval(start: utc(2026, 4, 1), end: utc(2026, 6, 1))) {
            let before = ZodiacSign.from(longitude: Ephemeris.longitude(of: .moon,
                                                                        at: p.end.addingTimeInterval(-60)))
            let after = ZodiacSign.from(longitude: Ephemeris.longitude(of: .moon,
                                                                       at: p.end.addingTimeInterval(60)))
            #expect(before == p.sign, "period claims \(p.sign.name) but the Moon was in \(before.name)")
            #expect(after != p.sign, "the Moon had not left \(p.sign.name) at the period's end")
        }
    }

    /// And it starts at an exact aspect — the separation at `start` really is the aspect's angle.
    @Test func everyPeriodStartsAtAnExactAspect() {
        for p in VoidOfCourse.periods(in: DateInterval(start: utc(2026, 4, 1), end: utc(2026, 6, 1))) {
            guard let body = p.lastBody, let aspect = p.lastAspect else { continue }
            let sep = abs(AstroMath.norm180(RootFinding.signedSeparation(.moon, body, at: p.start)))
            let off = abs(sep - aspect.angle)
            #expect(off < 0.02,
                    "\(aspect.name) to \(body.name) is \(String(format: "%.4f", sep))° at the start")
        }
    }

    /// Periods tile forward without overlapping. An overlap would mean the Moon was void in two
    /// signs at once.
    @Test func periodsAreOrderedAndDoNotOverlap() {
        let periods = VoidOfCourse.periods(in: DateInterval(start: utc(2026, 1, 1), end: utc(2026, 4, 1)))
        for p in periods { #expect(p.end > p.start, "period at \(p.start) has no duration") }
        for (a, b) in zip(periods, periods.dropFirst()) {
            #expect(b.start >= a.end, "\(b.start) overlaps the period ending \(a.end)")
        }
    }

    // MARK: - The definitional choice

    /// **Adding bodies can only shorten a void, never lengthen it.**
    ///
    /// A strict invariant rather than a preference: the modern set is a superset, so any aspect the
    /// traditional search found is still found, and there may now be a *later* one. This is what
    /// makes the two definitions comparable rather than merely different, and it fails immediately
    /// if the body list is not actually reaching the search.
    @Test func theModernSetNeverProducesALongerVoidThanTheTraditionalOne() {
        let window = DateInterval(start: utc(2026, 1, 1), end: utc(2026, 4, 1))
        let traditional = VoidOfCourse.periods(in: window, bodies: VoidOfCourse.traditional)
        let modern = VoidOfCourse.periods(in: window, bodies: VoidOfCourse.modern)

        #expect(modern.count <= traditional.count,
                "the modern set cannot create voids: \(modern.count) vs \(traditional.count)")

        var shortened = 0
        for m in modern {
            guard let t = traditional.first(where: { $0.end == m.end }) else {
                Issue.record("modern period ending \(m.end) has no traditional counterpart"); continue
            }
            #expect(m.start >= t.start - 1,
                    "the modern void in \(m.sign.name) starts EARLIER than the traditional one")
            if m.start > t.start + 60 { shortened += 1 }
        }
        // And the two must genuinely differ somewhere over a quarter, or the body list is inert.
        #expect(shortened > 0, "the outer planets changed nothing in three months — is `bodies` used?")
    }

    @Test func theStructuralConstantsMatchTheDefinition() {
        let o = Oracles.require("voc-lilly-definition")
        #expect(o.matches("ptolemaicAspects", Double(AspectType.all.count)))
        #expect(o.matches("traditionalBodies", Double(VoidOfCourse.traditional.count)))
        #expect(o.matches("modernBodies", Double(VoidOfCourse.modern.count)))
        #expect(!VoidOfCourse.traditional.contains(.moon), "the Moon cannot aspect itself")
    }

    @Test func aTropicalMonthHoldsTwelveOrThirteenPeriods() {
        let o = Oracles.require("voc-frequency")
        let start = utc(2026, 5, 1)
        let month = DateInterval(start: start, end: start.addingTimeInterval(27.32 * 86_400))
        let count = VoidOfCourse.periods(in: month).count
        #expect(o.matches("perMonth", Double(count)), "found \(count) periods in a tropical month")
    }

    // MARK: - Current

    @Test func currentAgreesWithTheEnclosingPeriod() {
        let window = DateInterval(start: utc(2026, 2, 1), end: utc(2026, 2, 20))
        for p in VoidOfCourse.periods(in: window) {
            let inside = p.start.addingTimeInterval(p.duration / 2)
            guard let found = VoidOfCourse.current(at: inside) else {
                Issue.record("no current period at \(inside), inside one from \(p.start)"); continue
            }
            #expect(abs(found.start.timeIntervalSince(p.start)) < 1)
            #expect(found.sign == p.sign)
        }
        // And outside one, there is none: an instant just after an ingress is never void, because
        // the Moon has a fresh sign to aspect through.
        let notVoid = VoidOfCourse.periods(in: window).map { $0.end.addingTimeInterval(60) }
        for t in notVoid {
            #expect(VoidOfCourse.current(at: t) == nil, "\(t) is just past an ingress, not void")
        }
    }
}
