import Testing
@testable import ConvertKit

// Oracle = exact published unit factors (NIST SP 811; ICAO nm = 1.852 km exactly;
// ft = 0.3048 m exactly; lb = 0.45359237 kg exactly; US gal = 3.785411784 L exactly).
@Suite("Convert — exact aviation unit factors")
struct ConvertTests {
    let tol = 1e-6

    @Test func temperature() {
        #expect(abs(Convert.cToF(0) - 32) < tol)
        #expect(abs(Convert.cToF(100) - 212) < tol)
        #expect(abs(Convert.fToC(32) - 0) < tol)
        #expect(abs(Convert.cToF(-40) - -40) < tol)   // the crossover
    }

    @Test func distance() {
        #expect(abs(Convert.nmToKm(100) - 185.2) < tol)
        #expect(abs(Convert.nmToSm(100) - 115.078) < tol)
        #expect(abs(Convert.ftToM(1000) - 304.8) < tol)
        #expect(abs(Convert.mToFt(Convert.ftToM(1234)) - 1234) < 1e-6)   // round-trip
    }

    @Test func weightAndFuel() {
        #expect(abs(Convert.lbToKg(100) - 45.359237) < tol)
        #expect(abs(Convert.avgasGalToLb(30) - 180) < tol)
        #expect(abs(Convert.jetAGalToLb(100) - 670) < tol)
        #expect(abs(Convert.galToLitre(1) - 3.785411784) < tol)
    }

    @Test func speed() {
        #expect(abs(Convert.ktToMph(100) - 115.078) < tol)
        #expect(abs(Convert.mphToKt(Convert.ktToMph(250)) - 250) < 1e-6)
    }

    @Test func climbGradient() {
        #expect(abs(Convert.ftPerNmToPercent(300) - 4.9374) < 1e-3)
        #expect(abs(Convert.ftPerNmToDegrees(300) - 2.8272) < 1e-3)
        #expect(abs(Convert.percentToFtPerNm(Convert.ftPerNmToPercent(500)) - 500) < 1e-6)
    }
}
