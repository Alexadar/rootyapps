import Testing
import CoreGraphics
import Foundation
@testable import monstro_client

@MainActor
struct CombatMathTests {
    @Test func basicArmorSubtraction() {
        // Non-4th hit: actual = max(incoming - defense, 0)
        #expect(approxEqual(CombatMath.actualDamage(incoming: 10, defense: 3, hitCount: 1), 7))
    }

    @Test func defenseExceedsDamageClampsToZero() {
        #expect(approxEqual(CombatMath.actualDamage(incoming: 5, defense: 9, hitCount: 1), 0))
    }

    @Test func everyFourthHitAppliesMinimumDamage() {
        // 4th hit with full armor still applies 0.4 floor.
        #expect(approxEqual(CombatMath.actualDamage(incoming: 5, defense: 9, hitCount: 4), 0.4))
        #expect(approxEqual(CombatMath.actualDamage(incoming: 5, defense: 9, hitCount: 8), 0.4))
    }

    @Test func fourthHitStillPrefersRealDamageWhenLarger() {
        #expect(approxEqual(CombatMath.actualDamage(incoming: 10, defense: 3, hitCount: 4), 7))
    }
}

@MainActor
struct MovementMathTests {
    let sprite = CGSize(width: 60, height: 60)
    let map = CGSize(width: 1000, height: 1000)

    @Test func zeroMovementKeepsPosition() {
        let p = CGPoint(x: 12, y: 34)
        let next = MovementMath.nextPosition(from: p, movement: .zero, speed: 300, deltaTime: 1, spriteSize: sprite, mapSize: map)
        #expect(next == p)
    }

    @Test func straightMovementUsesFullSpeed() {
        let next = MovementMath.nextPosition(from: .zero, movement: CGVector(dx: 1, dy: 0), speed: 100, deltaTime: 1, spriteSize: sprite, mapSize: map)
        #expect(approxEqual(next.x, 100))
        #expect(approxEqual(next.y, 0))
    }

    @Test func diagonalMovementApplies075Multiplier() {
        // Normalized diagonal component is ~0.7071; with the 0.75 multiplier each axis moves 0.7071*100*0.75.
        let next = MovementMath.nextPosition(from: .zero, movement: CGVector(dx: 1, dy: 1), speed: 100, deltaTime: 1, spriteSize: sprite, mapSize: map)
        let expected = (1.0 / 2.0.squareRoot()) * 100 * 0.75
        #expect(approxEqual(next.x, CGFloat(expected), 1e-4))
        #expect(approxEqual(next.y, CGFloat(expected), 1e-4))
    }

    @Test func clampsToMapBounds() {
        // From near the right edge, moving right should clamp to maxX = 500 - 30.
        let next = MovementMath.nextPosition(from: CGPoint(x: 460, y: 0), movement: CGVector(dx: 1, dy: 0), speed: 100, deltaTime: 1, spriteSize: sprite, mapSize: map)
        #expect(approxEqual(next.x, 470))
    }

    @Test func clampHelperCentersWithinBounds() {
        let clamped = MovementMath.clamp(position: CGPoint(x: 10_000, y: -10_000), spriteSize: sprite, mapSize: map)
        #expect(approxEqual(clamped.x, 470))
        #expect(approxEqual(clamped.y, -470))
    }
}

@MainActor
struct SpreadMathTests {
    @Test func zeroDeviationIsZeroAngle() {
        #expect(approxEqual(SpreadMath.deviationToAngle(0), 0))
    }

    @Test func deviationEqualToReferenceIsQuarterPi() {
        #expect(approxEqual(SpreadMath.deviationToAngle(500, referenceDistance: 500), .pi / 4))
    }

    @Test func angleIncreasesWithDeviation() {
        #expect(SpreadMath.deviationToAngle(100) < SpreadMath.deviationToAngle(200))
    }
}

@MainActor
struct CameraMathTests {
    let map = CGSize(width: 2000, height: 2000)
    let viewport = CGSize(width: 800, height: 600)

    @Test func interpolatesTowardTargetWhenInsideBounds() {
        let pos = CameraMath.clampedPosition(target: CGPoint(x: 100, y: 100), current: .zero, mapSize: map, viewportSize: viewport, smoothing: 0.1)
        #expect(approxEqual(pos.x, 10))
        #expect(approxEqual(pos.y, 10))
    }

    @Test func clampsAtMapCorner() {
        // smoothing 1.0 -> target is taken directly, then clamped to camera limits.
        let pos = CameraMath.clampedPosition(target: CGPoint(x: 5000, y: 5000), current: .zero, mapSize: map, viewportSize: viewport, smoothing: 1.0)
        #expect(approxEqual(pos.x, 600))   // mapMax 1000 - viewport/2 400
        #expect(approxEqual(pos.y, 700))   // mapMax 1000 - viewport/2 300
    }

    @Test func centersWhenViewportLargerThanMap() {
        let small = CGSize(width: 500, height: 500)
        let pos = CameraMath.clampedPosition(target: CGPoint(x: 999, y: 999), current: .zero, mapSize: small, viewportSize: viewport, smoothing: 1.0)
        #expect(pos == .zero)
    }
}

@MainActor
struct SteeringMathTests {
    @Test func returnsNilWhenWithinStopDistance() {
        let r = SteeringMath.step(from: .zero, toward: CGPoint(x: 5, y: 0), velocity: .zero, speed: 100, turnRate: 34, rotationOffset: 0, useDirectSteering: true, stopDistance: 10, deltaTime: 1)
        #expect(r == nil)
    }

    @Test func directSteeringMovesAtSpeedTowardTarget() {
        let r = SteeringMath.step(from: .zero, toward: CGPoint(x: 100, y: 0), velocity: .zero, speed: 50, turnRate: 34, rotationOffset: 0, useDirectSteering: true, stopDistance: 10, deltaTime: 1)
        let result = try! #require(r)
        #expect(approxEqual(result.velocity.dx, 50))
        #expect(approxEqual(result.velocity.dy, 0))
        #expect(approxEqual(result.position.x, 50))
        #expect(approxEqual(result.rotation, 0))
    }

    @Test func directSteeringVelocityMagnitudeEqualsSpeed() {
        let r = SteeringMath.step(from: .zero, toward: CGPoint(x: 30, y: 40), velocity: .zero, speed: 100, turnRate: 34, rotationOffset: 0, useDirectSteering: true, stopDistance: 1, deltaTime: 1)
        let result = try! #require(r)
        let mag = sqrt(result.velocity.dx * result.velocity.dx + result.velocity.dy * result.velocity.dy)
        #expect(approxEqual(mag, 100, 1e-4))
    }

    @Test func arcSteeringRenormalizesToSpeed() {
        let r = SteeringMath.step(from: .zero, toward: CGPoint(x: 0, y: 100), velocity: CGVector(dx: 100, dy: 0), speed: 100, turnRate: 34, rotationOffset: 0, useDirectSteering: false, stopDistance: 1, deltaTime: 1)
        let result = try! #require(r)
        let mag = sqrt(result.velocity.dx * result.velocity.dx + result.velocity.dy * result.velocity.dy)
        #expect(approxEqual(mag, 100, 1e-4))
    }

    @Test func rotationOffsetIsApplied() {
        let r = SteeringMath.step(from: .zero, toward: CGPoint(x: 100, y: 0), velocity: .zero, speed: 50, turnRate: 34, rotationOffset: .pi / 2, useDirectSteering: true, stopDistance: 1, deltaTime: 1)
        let result = try! #require(r)
        #expect(approxEqual(result.rotation, .pi / 2))
    }
}
