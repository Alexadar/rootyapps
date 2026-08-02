import Testing
@testable import NavKit

// Oracle = time–speed–distance arithmetic (FAA-H-8083-25 PHAK, "Navigation":
// https://www.faa.gov/regulations_policies/handbooks_manuals/aviation/phak).
@Suite("Nav — time / speed / distance")
struct NavTests {
    @Test func time()  { #expect(abs(Nav.timeMin(distanceNm: 150, gsKt: 120) - 75) < 1e-9) }
    @Test func dist()  { #expect(abs(Nav.distanceNm(gsKt: 120, timeMin: 30) - 60) < 1e-9) }
    @Test func speed() { #expect(abs(Nav.groundspeedKt(distanceNm: 100, timeMin: 40) - 150) < 1e-9) }
    @Test func zeroSpeedIsSafe() { #expect(Nav.timeMin(distanceNm: 10, gsKt: 0) == 0) }
}
