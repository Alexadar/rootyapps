import Testing
import Foundation
@testable import WindKit

// Oracle = wind-triangle trigonometry as taught in FAA-H-8083-25 Pilot's Handbook of
// Aeronautical Knowledge, "Navigation" chapter (https://www.faa.gov/regulations_policies/
// handbooks_manuals/aviation/phak). Expected values are the closed-form vector solution;
// the degenerate head/tail/crosswind cases are the textbook sanity checks.
@Suite("Wind — wind triangle (FAA PHAK)")
struct WindTests {
    let tol = 0.01

    @Test func directHeadwindSubtractsFromGroundspeed() {
        let s = Wind.solution(courseDeg: 360, tasKt: 100, windDirDeg: 360, windSpeedKt: 20)!
        #expect(abs(s.wcaDeg - 0) < tol)
        #expect(abs(s.gsKt - 80) < tol)          // 100 − 20
        #expect(abs(s.headingDeg - 0) < tol)     // no crab
    }

    @Test func directTailwindAddsToGroundspeed() {
        let s = Wind.solution(courseDeg: 360, tasKt: 100, windDirDeg: 180, windSpeedKt: 20)!
        #expect(abs(s.wcaDeg - 0) < tol)
        #expect(abs(s.gsKt - 120) < tol)         // 100 + 20
    }

    @Test func directCrosswindFromRightCrabsRight() {
        // Course 360, wind from 090 (due right) at 20 kt, TAS 100.
        let s = Wind.solution(courseDeg: 360, tasKt: 100, windDirDeg: 90, windSpeedKt: 20)!
        #expect(abs(s.wcaDeg - 11.5370) < tol)   // asin(0.2)
        #expect(abs(s.gsKt - 97.9796) < tol)     // 100·√0.96
        #expect(abs(s.headingDeg - 11.5370) < tol)
    }

    @Test func workedQuarteringWind() {
        // Course 090, TAS 120, wind from 180 at 30 kt (from the right of an eastbound leg).
        let s = Wind.solution(courseDeg: 90, tasKt: 120, windDirDeg: 180, windSpeedKt: 30)!
        #expect(abs(s.wcaDeg - 14.4775) < tol)   // asin(0.25)
        #expect(abs(s.headingDeg - 104.4775) < tol)
        #expect(abs(s.gsKt - 116.1895) < tol)    // 120·√0.9375
    }

    @Test func crosswindTooStrongIsUnsolvable() {
        // Direct 90° crosswind of 120 kt against 100 kt TAS cannot hold course.
        #expect(Wind.solution(courseDeg: 360, tasKt: 100, windDirDeg: 90, windSpeedKt: 120) == nil)
    }

    @Test func runwayComponents() {
        let c = Wind.components(runwayHeadingDeg: 360, windDirDeg: 40, windSpeedKt: 20)
        #expect(abs(c.headwindKt - 15.3209) < tol)   // 20·cos40°
        #expect(abs(c.crosswindKt - 12.8558) < tol)  // 20·sin40°  (from the right)
    }

    @Test func crosswindFromLeftIsNegative() {
        // Runway 090, wind from due north (000): pure crosswind from the left.
        let c = Wind.components(runwayHeadingDeg: 90, windDirDeg: 0, windSpeedKt: 10)
        #expect(abs(c.headwindKt - 0) < tol)
        #expect(abs(c.crosswindKt - -10) < tol)
    }

    @Test func deriveWindRoundTrips() {
        // Inverse of the worked quartering example → wind from 180 at 30 kt.
        let w = Wind.derive(courseDeg: 90, headingDeg: 104.4775, tasKt: 120, gsKt: 116.1895)
        #expect(abs(w.windDirDeg - 180) < 0.05)
        #expect(abs(w.windSpeedKt - 30) < 0.05)
    }

    @Test func deriveHeadwind() {
        let w = Wind.derive(courseDeg: 360, headingDeg: 0, tasKt: 100, gsKt: 80)
        #expect(abs(w.windDirDeg - 0) < 0.05)        // from the north (360 ≡ 0)
        #expect(abs(w.windSpeedKt - 20) < 0.05)
    }
}
