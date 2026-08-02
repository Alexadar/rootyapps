import Testing
import Foundation
import DayCountKit

/// The Kit-level half of the tape's correctness requirement (`par/plan_tape.md` §3): a saved tape stores
/// the dates and convention of every dated solve and re-derives the day count on reopening. Dates must
/// round-trip exactly and a corrupt file must throw — a persisted February 31st has to be an error the
/// app can report, not a trap.
///
/// ORACLES:
///  • IDENTITY — encode/decode is the identity on `YearMonthDay` and `Convention`; `days` is pure.
///  • INVARIANT — impossible persisted dates throw a `DecodingError`.
@Suite("Tape replay — codability and determinism")
struct ReplayTests {

    @Test("dates and conventions replay to the identical day count",
          arguments: Oracles.isdaRows.map(\.id))
    func replayIsBitForBit(id: String) throws {
        let o = Oracles.require(id)
        func decode(_ encoded: Double) -> DayCount.YearMonthDay {
            let n = Int(encoded.rounded())
            return DayCount.YearMonthDay(n / 10000, (n / 100) % 100, n % 100)
        }
        let start = decode(o.input("start")), end = decode(o.input("end"))

        let encoder = JSONEncoder()
        let restoredStart = try JSONDecoder().decode(
            DayCount.YearMonthDay.self, from: encoder.encode(start)
        )
        let restoredEnd = try JSONDecoder().decode(
            DayCount.YearMonthDay.self, from: encoder.encode(end)
        )
        #expect(restoredStart == start)
        #expect(restoredEnd == end)

        for convention in DayCount.Convention.allCases {
            let restoredConvention = try JSONDecoder().decode(
                DayCount.Convention.self, from: encoder.encode(convention)
            )
            #expect(restoredConvention == convention)
            let termination = DayCount.YearMonthDay(2009, 2, 28)
            #expect(DayCount.days(from: restoredStart, to: restoredEnd,
                                  convention: restoredConvention, terminationDate: termination)
                    == DayCount.days(from: start, to: end,
                                     convention: convention, terminationDate: termination))
        }
    }

    @Test func corruptPersistedDatesThrow() {
        let corrupt = [
            #"{"year":2019,"month":2,"day":29}"#,   // not a leap year
            #"{"year":2020,"month":13,"day":1}"#,
            #"{"year":2020,"month":0,"day":10}"#,
            #"{"year":2020,"month":6,"day":31}"#,
            #"{"year":2020,"month":6}"#,
        ]
        for json in corrupt {
            #expect(throws: (any Error).self) {
                _ = try JSONDecoder().decode(DayCount.YearMonthDay.self, from: Data(json.utf8))
            }
        }
        // …and a valid one still decodes, including a real leap day.
        #expect(throws: Never.self) {
            _ = try JSONDecoder().decode(
                DayCount.YearMonthDay.self, from: Data(#"{"year":2020,"month":2,"day":29}"#.utf8)
            )
        }
    }
}
