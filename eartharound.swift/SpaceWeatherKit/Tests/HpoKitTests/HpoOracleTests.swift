import Testing
import Foundation
@testable import HpoKit

/// ORACLE = GFZ Potsdam Hpo (Hp30/Hp60) index definition.
///
///  • Hp30 is sampled every 30 min ⇒ 48 intervals per UT day; Hp60 every 60 min ⇒ 24.
///  • Days are delimited at 00:00 UTC; slot i covers [i·cadence, (i+1)·cadence).
///  • Hpo shares the Kp amplitude scale but is open-ended (values may exceed 9);
///    within 0…9 its ap-equivalent follows the standard Bartels table.
///  Source: GFZ "Hpo — Hp30 and Hp60 indices" definition, kp.gfz.de.
@Suite("Hpo oracle — GFZ high-cadence structure")
struct HpoOracleTests {

    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()
    static func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    @Test func cadenceStructure() {
        #expect(Hpo.Cadence.hp30.slotsPerDay == 48)
        #expect(Hpo.Cadence.hp60.slotsPerDay == 24)
        #expect(Hpo.Cadence.hp30.minutes == 30)
    }

    @Test func slotIndexBoundaries() {
        #expect(Hpo.slotIndex(for: Self.date(2026, 7, 4, 0, 0), cadence: .hp30) == 0)
        #expect(Hpo.slotIndex(for: Self.date(2026, 7, 4, 0, 29), cadence: .hp30) == 0)
        #expect(Hpo.slotIndex(for: Self.date(2026, 7, 4, 0, 30), cadence: .hp30) == 1)
        #expect(Hpo.slotIndex(for: Self.date(2026, 7, 4, 23, 30), cadence: .hp30) == 47)
        #expect(Hpo.slotIndex(for: Self.date(2026, 7, 4, 23, 0), cadence: .hp60) == 23)
    }

    @Test func utDayBoundaryAt0000UTC() {
        let lastSlotOfDay = Self.date(2026, 7, 4, 23, 59)
        let firstOfNext = Self.date(2026, 7, 5, 0, 0)
        #expect(Hpo.utDayStart(for: lastSlotOfDay) == Self.date(2026, 7, 4, 0, 0))
        #expect(Hpo.utDayStart(for: firstOfNext) == Self.date(2026, 7, 5, 0, 0))
        #expect(Hpo.utDayStart(for: lastSlotOfDay) != Hpo.utDayStart(for: firstOfNext))
    }

    @Test func groupingSlotsAndPadsGaps() {
        let readings = [
            Hpo.Reading(time: Self.date(2026, 7, 4, 0, 0), value: 3.0),   // slot 0
            Hpo.Reading(time: Self.date(2026, 7, 4, 1, 0), value: 5.333), // slot 2
            Hpo.Reading(time: Self.date(2026, 7, 5, 0, 30), value: 6.0),  // next day, slot 1
        ]
        let days = Hpo.groupByUTDay(readings, cadence: .hp30)
        #expect(days.count == 2)
        #expect(days[0].values.count == 48)
        #expect(days[0].values[0] == 3.0)
        #expect(days[0].values[1] == nil)          // gap padded
        #expect(days[0].values[2] == 5.333)
        #expect(days[1].values[1] == 6.0)
    }

    @Test func rollingWindow() {
        let end = Self.date(2026, 7, 4, 12, 0)
        let readings = (0..<48).map {
            Hpo.Reading(time: Self.date(2026, 7, 4, 0, 0).addingTimeInterval(Double($0) * 1800), value: Double($0) / 10)
        }
        let last3h = Hpo.window(readings, hours: 3, endingAt: end)
        #expect(last3h.count == 6)                          // six 30-min samples in 3h
        #expect(last3h.first!.time == Self.date(2026, 7, 4, 9, 30))
        #expect(last3h.last!.time == end)
    }

    @Test func classificationSharesBartelsAndNOAA() {
        #expect(Hpo.gScale(forHp: 5.0) == 1)
        #expect(Hpo.gScale(forHp: 9.0) == 5)
        #expect(Hpo.gScale(forHp: 11.0) == 5)      // open-ended value still saturates G5
        #expect(Hpo.apEquivalent(forHp: 5.0) == 48) // Bartels 5o
        #expect(Hpo.apEquivalent(forHp: 9.0) == 400)
        #expect(Hpo.apEquivalent(forHp: 12.0) == nil) // beyond published table — don't fabricate
        #expect(Hpo.exceedsKpCeiling(11.0))
        #expect(!Hpo.exceedsKpCeiling(8.0))
    }
}
