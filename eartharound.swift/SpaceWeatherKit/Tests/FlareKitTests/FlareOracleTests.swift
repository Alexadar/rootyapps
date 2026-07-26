import Testing
import Foundation
@testable import FlareKit

/// ORACLE = NOAA SWPC / GOES solar-flare classification and the NOAA R-scale.
///
///  • Flare class boundaries (GOES 0.1–0.8 nm peak flux, W/m², decade-log):
///      A ≥ 1e-8, B ≥ 1e-7, C ≥ 1e-6, M ≥ 1e-5, X ≥ 1e-4.
///    Sub-scale is linear within the decade: 1.0e-7 = B1.0, 9.9e-6 = C9.9,
///    2.5e-5 = M2.5, 1.0e-4 = X1.0.
///    Source: NOAA SWPC "Solar Flares (Radio Blackouts)" / GOES X-ray flux definition.
///  • R-scale: R1=M1 (1e-5), R2=M5 (5e-5), R3=X1 (1e-4), R4=X10 (1e-3), R5=X20 (2e-3).
///    Source: NOAA "Space Weather Scales" (Radio Blackouts R).
///  • S-scale (solar radiation storms), severity wording:
///      S1 Minor, S2 Moderate, S3 Strong, S4 Severe, S5 Extreme
///      (≥10 MeV proton flux 10, 10², 10³, 10⁴, 10⁵ pfu respectively).
///    Source: NOAA "Space Weather Scales" (Solar Radiation Storms S). The app receives the
///    S level already computed in NOAA's scales feed, so only the wording is under test.
@Suite("Flare oracle — GOES class boundaries + NOAA R-scale")
struct FlareOracleTests {

    @Test func workedSubScaleValues() {
        #expect(Flare.classify(fluxWm2: 1.0e-7).label == "B1.0")
        #expect(Flare.classify(fluxWm2: 9.9e-6).label == "C9.9")
        #expect(Flare.classify(fluxWm2: 2.5e-5).label == "M2.5")
        #expect(Flare.classify(fluxWm2: 1.0e-4).label == "X1.0")
        #expect(Flare.classify(fluxWm2: 1.0e-8).label == "A1.0")
    }

    @Test func classBoundariesAreDecadeLog() {
        #expect(Flare.classify(fluxWm2: 9.9e-8).letter == "A")   // 9.9e-8 < 1e-7 ⇒ still A (A9.9)
        #expect(Flare.classify(fluxWm2: 9.9e-7).letter == "B")   // top of B
        #expect(Flare.classify(fluxWm2: 1.0e-6).letter == "C")   // C floor
        #expect(Flare.classify(fluxWm2: 9.99e-6).letter == "C")  // just under M
        #expect(Flare.classify(fluxWm2: 1.0e-5).letter == "M")   // M floor
        #expect(Flare.classify(fluxWm2: 1.0e-4).letter == "X")   // X floor
    }

    @Test func bigXKeepsClimbing() {
        // X20 = 2e-3 (a great historical flare); magnitude exceeds 10.
        #expect(Flare.classify(fluxWm2: 2.0e-3).label == "X20")
        #expect(Flare.classify(fluxWm2: 4.5e-4).label == "X4.5")
    }

    @Test func classStringRoundTrips() {
        for label in ["B1.0", "C9.9", "M2.5", "X1.0", "M1.4"] {
            let flux = try! #require(Flare.flux(forClass: label))
            #expect(Flare.classify(fluxWm2: flux).label == label, "round-trip \(label)")
        }
        #expect(Flare.flux(forClass: "banana") == nil)
    }

    @Test func rScaleMatchesNOAA() {
        #expect(Flare.rScale(fluxWm2: 9.9e-6) == 0)  // below M1
        #expect(Flare.rScale(fluxWm2: 1e-5) == 1)    // M1 → R1
        #expect(Flare.rScale(fluxWm2: 5e-5) == 2)    // M5 → R2
        #expect(Flare.rScale(fluxWm2: 1e-4) == 3)    // X1 → R3
        #expect(Flare.rScale(fluxWm2: 1e-3) == 4)    // X10 → R4
        #expect(Flare.rScale(fluxWm2: 2e-3) == 5)    // X20 → R5
        #expect(Flare.rScale(forClass: "X1.0") == 3)
        #expect(Flare.rScale(forClass: "M1.0") == 1)
    }

    @Test func scaleLabelsUseNOAASeverityWording() {
        // R and S share the published severity ladder; both must read it the same way.
        #expect(Flare.rLabel(0) == "Below R1")
        #expect((1...5).map(Flare.rLabel) ==
                ["R1 Minor", "R2 Moderate", "R3 Strong", "R4 Severe", "R5 Extreme"])
        #expect(Flare.sLabel(0) == "Below S1")
        #expect((1...5).map(Flare.sLabel) ==
                ["S1 Minor", "S2 Moderate", "S3 Strong", "S4 Severe", "S5 Extreme"])
        // Out-of-range levels must not fabricate a storm.
        #expect(Flare.sLabel(-1) == "Below S1")
        #expect(Flare.sLabel(9) == "Below S1")
    }
}
