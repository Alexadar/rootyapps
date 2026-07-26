import Testing
import Foundation
@testable import ClimbDescentKit

// Oracle = descent/gradient geometry (FAA-H-8083-25 PHAK) with 1 nm = 6076.115 ft.
@Suite("Climb/Descent — rates & gradients")
struct ClimbDescentTests {
    let tol = 1e-3

    @Test func descentRate() {
        // Lose 3,000 ft over 10 nm at 120 kt → 5 min → 600 fpm.
        #expect(abs(ClimbDescent.descentRateFpm(altitudeToLoseFt: 3000, distanceNm: 10, gsKt: 120) - 600) < tol)
    }
    @Test func requiredRate() {
        #expect(abs(ClimbDescent.rateFpm(gradientFtPerNm: 500, gsKt: 90) - 750) < tol)
    }
    @Test func topOfDescent() {
        #expect(abs(ClimbDescent.topOfDescentNm(altitudeToLoseFt: 9000, gradientFtPerNm: 300) - 30) < tol)
    }
    @Test func gradientPercentAndDegrees() {
        #expect(abs(ClimbDescent.gradientPercent(ftPerNm: 300) - 4.9374) < tol)
        #expect(abs(ClimbDescent.gradientDegrees(ftPerNm: 300) - 2.8272) < tol)
    }
    @Test func glideDistance() {
        // 9:1 glide from 5,000 ft ≈ 7.41 nm.
        #expect(abs(ClimbDescent.glideDistanceNm(glideRatio: 9, heightFt: 5000) - 7.4059) < tol)
    }
}
