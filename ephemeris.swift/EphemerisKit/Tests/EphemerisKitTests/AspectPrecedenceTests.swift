import Testing
import Foundation
@testable import EphemerisKit

/// The two detectors must answer the same question the same way.
///
/// `detect(in:)` and `detect(between:and:)` both decide "which aspect is this separation?" and they
/// used to disagree: the first kept whichever type appeared earliest in `AspectType.all`, the second
/// kept the closest. Convention is exactness — the aspect a separation is *nearest* to wins — so the
/// first was brought into line.
///
/// Unreachable through the app (overlap needs orbFactor ≥ 2.5, the slider stops at 1.6) but reachable
/// through the Kit, and a divergence between two functions doing one job is exactly what produced the
/// backwards zodiac that `ChartGeometry` exists to prevent.
@Suite("Aspect precedence")
struct AspectPrecedenceTests {

    private func pair(_ separation: Double) -> [BodyPosition] {
        [BodyPosition(body: .sun, longitude: 0, speed: 1),
         BodyPosition(body: .mars, longitude: separation, speed: 1)]
    }

    /// 78° sits inside both a square (12° off) and a sextile (18° off) once the orb factor is wide
    /// enough. It is a square, because it is nearer one.
    @Test func overlapResolvesToTheNearerAspect() {
        let hit = Aspects.detect(in: pair(78), orbFactor: 5.0)
        #expect(hit.count == 1)
        #expect(hit.first?.type.name == "Square")
        #expect((hit.first?.orb ?? 0) == 12)
    }

    /// The same separation through the cross-set detector must agree.
    @Test func bothDetectorsAgreeAcrossTheOverlapRange() {
        for separation in stride(from: 0.0, through: 180.0, by: 0.5) {
            for factor in [1.0, 1.6, 2.5, 3.0, 5.0] {
                let within = Aspects.detect(in: pair(separation), orbFactor: factor)
                let across = Aspects.detect(between: [pair(separation)[0]],
                                            and: [pair(separation)[1]],
                                            orbFactor: factor)
                #expect(within.first?.type.name == across.first?.type.name,
                        "detectors disagree at \(separation)° factor \(factor): \(within.first?.type.name ?? "none") vs \(across.first?.type.name ?? "none")")
            }
        }
    }

    /// At every factor the app can actually produce, no separation is claimed by two types — so this
    /// change cannot alter a single chart a user has ever seen.
    @Test func noOverlapExistsWithinTheAppsOrbRange() {
        for separation in stride(from: 0.0, through: 180.0, by: 0.1) {
            for factor in stride(from: 0.5, through: 1.6, by: 0.1) {
                let inOrb = AspectType.all.filter { abs(separation - $0.angle) <= $0.baseOrb * factor }
                #expect(inOrb.count <= 1,
                        "separation \(separation)° matches \(inOrb.count) types at factor \(factor)")
            }
        }
    }

    /// The first factor at which any two aspects collide, asserted so the claim in the doc comment
    /// stays true if anyone edits the base orbs.
    @Test func firstOverlapIsAboveTheSliderCeiling() {
        var firstOverlap = Double.infinity
        for factor in stride(from: 0.5, through: 6.0, by: 0.01) {
            let collides = stride(from: 0.0, through: 180.0, by: 0.1).contains { s in
                AspectType.all.filter { abs(s - $0.angle) <= $0.baseOrb * factor }.count > 1
            }
            if collides { firstOverlap = factor; break }
        }
        #expect(firstOverlap > 1.6, "the orb slider ceiling is 1.6; overlap begins at \(firstOverlap)")
    }
}
