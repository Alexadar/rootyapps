import Testing
import SpriteKit
@testable import monstro_client

@MainActor
struct BulletTests {
    func makeBullet(penetration: Int, range: CGFloat) -> Bullet {
        let info = BulletInfo(
            damage: 10, speed: 800, range: range, deviation: 0,
            penetration: penetration, startScale: 1, maxScale: 1, scaleGrowth: 0,
            textureName: "bullet_test"
        )
        return Bullet(sprite: SKSpriteNode(), info: info, startPosition: .zero)
    }

    @Test func penetrationCountsDownThenStops() {
        let b = makeBullet(penetration: 2, range: 1000)
        #expect(b.canPenetrate())   // hit 1 of 2
        #expect(b.canPenetrate())   // hit 2 of 2
        #expect(!b.canPenetrate())  // hit 3 exceeds penetration
    }

    @Test func expiresAfterPenetrationExhausted() {
        let b = makeBullet(penetration: 2, range: 1000)
        #expect(!b.isExpired())
        _ = b.canPenetrate()
        _ = b.canPenetrate()
        #expect(b.isExpired())   // hitCount (2) >= penetration (2)
    }

    @Test func expiresAfterTravelingRange() {
        let b = makeBullet(penetration: 5, range: 500)
        #expect(!b.isExpired())
        b.distanceTraveled = 500
        #expect(b.isExpired())   // distanceTraveled >= range
    }
}
