import Testing
import Foundation
import EphemerisKit

@Suite("Aspect calculator")
struct AspectsTests {

    private func pos(_ body: CelestialBody, _ lon: Double) -> BodyPosition {
        BodyPosition(body: body, longitude: lon, speed: 1)
    }

    @Test func angleHelpers() {
        #expect(AstroMath.norm360(-10) == 350)
        #expect(AstroMath.norm360(370) == 10)
        #expect(AstroMath.norm180(190) == -170)
        #expect(AstroMath.separation(350, 10) == 20)      // wraps the 0/360 seam
        #expect(AstroMath.separation(10, 350) == 20)      // symmetric
        #expect(abs(AstroMath.separation(0, 200) - 160) < 1e-9) // clamps to ≤180
    }

    @Test func exactAspects() {
        let p = [pos(.sun, 0), pos(.moon, 90), pos(.mars, 120), pos(.venus, 180)]
        let a = Aspects.detect(in: p, orbFactor: 1)
        #expect(a.contains { $0.type.name == "Square" && $0.orb < 1e-6 })
        #expect(a.contains { $0.type.name == "Trine" && $0.orb < 1e-6 })
        #expect(a.contains { $0.type.name == "Opposition" })
    }

    @Test func orbBoundary() {
        // Conjunction base orb = 8°. 7° in, 9° out at factor 1.0.
        let inOrb = Aspects.detect(in: [pos(.sun, 0), pos(.mercury, 7)], orbFactor: 1)
        #expect(inOrb.contains { $0.type.name == "Conjunction" })
        let outOrb = Aspects.detect(in: [pos(.sun, 0), pos(.mercury, 9)], orbFactor: 1)
        #expect(outOrb.isEmpty)
        // Shrinking the orb factor drops the 7° conjunction (7 > 8*0.8=6.4).
        let tightened = Aspects.detect(in: [pos(.sun, 0), pos(.mercury, 7)], orbFactor: 0.8)
        #expect(tightened.isEmpty)
    }

    @Test func sortedByTightness() {
        // Sun☌Moon (orb 3), Sun△Mars (orb 1), Moon△Mars (sep 116°, orb 4).
        let p = [pos(.sun, 0), pos(.moon, 3), pos(.mars, 119)]
        let a = Aspects.detect(in: p, orbFactor: 1)
        #expect(a.count == 3)
        for i in 1..<a.count { #expect(a[i - 1].orb <= a[i].orb) } // ascending
        #expect(a.first?.type.name == "Trine")  // tightest = Sun△Mars (orb 1)
        #expect(a.first?.orb ?? 99 < 1.0001)
    }
}
