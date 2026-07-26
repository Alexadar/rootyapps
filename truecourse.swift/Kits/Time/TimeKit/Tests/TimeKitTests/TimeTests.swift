import Testing
@testable import TimeKit

// Oracle = exact time arithmetic (60 min/hr, 24 hr/day; Zulu = local − UTC offset).
@Suite("Time — HMS / decimal / Zulu")
struct TimeTests {
    @Test func hmsToDecimal() {
        #expect(abs(FlightTime.hmsToDecimalHr(h: 1, m: 30, s: 0) - 1.5) < 1e-9)
        #expect(abs(FlightTime.hmsToDecimalHr(h: 2, m: 15, s: 36) - 2.26) < 1e-9)
    }
    @Test func decimalToHMS() {
        let t = FlightTime.decimalHrToHMS(2.5)
        #expect(t.h == 2 && t.m == 30 && t.s == 0)
    }
    @Test func zulu() {
        #expect(abs(FlightTime.zuluHour(localHour: 8, utcOffsetHr: -5) - 13) < 1e-9)   // EST
        #expect(abs(FlightTime.zuluHour(localHour: 2, utcOffsetHr: 3) - 23) < 1e-9)    // wraps to prev day
        #expect(abs(FlightTime.localHour(zuluHour: 13, utcOffsetHr: -5) - 8) < 1e-9)
    }
}
