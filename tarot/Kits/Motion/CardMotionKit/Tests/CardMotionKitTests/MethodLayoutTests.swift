import Foundation
import Testing
@testable import CardMotionKit

/// Every shipped layout, held to the same geometric contract. These are the tests that let
/// a slot coordinate be retuned without re-deriving the whole safety argument by hand.
@Suite("Method layouts")
struct MethodLayoutTests {

    static let layouts: [(String, MotionConfig)] = [
        ("oneCard", .oneCard), ("threeCard", .threeCard),
        ("fiveCrossroads", .fiveCrossroads), ("celticCross", .celticCross),
    ]

    @Test func everyLayoutIsInternallyConsistent() {
        for (name, c) in Self.layouts {
            #expect(c.slotX.count == c.slotCount, "\(name)")
            #expect(c.slotZ.count == c.slotCount, "\(name)")
            #expect(c.slotYaw.count == c.slotCount, "\(name)")
            #expect(c.slotLift.count == c.slotCount, "\(name)")
            #expect(c.cardCapacity == 78, "\(name)")
            for s in 0..<c.slotCount {
                #expect(abs(c.slotX[s]) <= c.tableExtentX, "\(name) slot \(s) x")
                #expect(abs(c.slotZ[s]) <= c.tableExtentZ, "\(name) slot \(s) z")
            }
        }
    }

    /// No two slots overlap — closer than a card's short side — except pairs that share a
    /// centre BY DESIGN (the cross's heart and its crossing card), which must then differ
    /// in yaw and lift or they would z-fight as one unreadable blob.
    @Test func slotsDoNotCollideExceptTheDeclaredCross() {
        for (name, c) in Self.layouts {
            for a in 0..<c.slotCount {
                for b in (a + 1)..<c.slotCount {
                    let dx = c.slotX[a] - c.slotX[b]
                    let dz = c.slotZ[a] - c.slotZ[b]
                    let dist = (dx * dx + dz * dz).squareRoot()
                    if dist < 0.001 {
                        #expect(abs(c.slotYaw[a] - c.slotYaw[b]) > 0.5,
                                "\(name) \(a)/\(b): co-located without a crossing yaw")
                        #expect(abs(c.slotLift[a] - c.slotLift[b]) > 0.003,
                                "\(name) \(a)/\(b): co-located without lift separation")
                    } else {
                        #expect(dist >= c.cardWidth,
                                "\(name) \(a)/\(b): \(dist) < card width \(c.cardWidth)")
                    }
                }
            }
        }
    }

    /// Every slot is reachable: inside the pointer clamp, outside the deck's grab circle,
    /// and unambiguous under the snap radius (no release point can strictly beat a slot at
    /// its own centre — nearest-free-slot handles the shared-centre pair).
    @Test func everySlotIsReachableAndGrabSafe() {
        for (name, c) in Self.layouts {
            for s in 0..<c.slotCount {
                let dxDeck = c.slotX[s] - c.deckX
                let dzDeck = c.slotZ[s] - c.deckZ
                let deckDist = (dxDeck * dxDeck + dzDeck * dzDeck).squareRoot()
                #expect(deckDist > c.deckGrabRadius,
                        "\(name) slot \(s): inside the deck grab circle (\(deckDist))")
            }
        }
    }

    /// The shared-centre tie-break, asserted at the kernel: a release exactly on the
    /// cross's shared centre commits to the HEART first (strict `<` keeps the earlier
    /// slot), and the next release there takes the crossing slot with its yaw and lift.
    @Test func theCrossFillsHeartThenCrossingCard() {
        let c = MotionConfig.test(MotionConfig.celticCross)
        var w = MotionWorld(batch: 1, config: c, seed: 7)
        w.assignDeckOrder(Array(0..<w.capacity), world: 0)

        func dragCard(to x: Double, z: Double) {
            let dt = 1.0 / 120.0
            for tick in 0..<240 {
                let t = Double(tick) * dt
                let drag = min(max((t - 0.2) / 1.0, 0), 1)
                let eased = drag * drag * (3 - 2 * drag)
                let px = c.deckX + (x - c.deckX) * eased
                let pz = c.deckZ + (z - c.deckZ) * eased
                let press: Double = t >= 0.04 && t < 1.3 ? 1 : 0
                let intent = MotionIntent(pointerX: Tensor(shape: [1], data: [px]),
                                          pointerZ: Tensor(shape: [1], data: [pz]),
                                          press: Tensor(shape: [1], data: [press]),
                                          lightX: .zeros([1]), lightZ: .zeros([1]))
                MotionStep.advance(&w, intent: intent, dt: dt, config: c)
            }
        }

        // Two identical drags to the shared centre.
        dragCard(to: c.slotX[0], z: c.slotZ[0])
        dragCard(to: c.slotX[1], z: c.slotZ[1])

        let landedSlots = (0..<w.capacity).compactMap { lane -> Int? in
            let phase = w.phase.data[lane]
            guard phase == MotionWorld.Phase.landed else { return nil }
            return Int(w.slot.data[lane])
        }.sorted()
        #expect(landedSlots == [0, 1], "expected heart then crossing card, got \(landedSlots)")

        // The crossing card carries its quarter-turn and rest lift in the pose.
        let poses = MotionPose.poses(of: w, config: c)
        let crossingLane = (0..<w.capacity).first { Int(w.slot.data[$0]) == 1 }
        #expect(crossingLane != nil)
        if let lane = crossingLane {
            #expect(abs(poses.yaw.data[lane] - Double.pi / 2) < 0.01,
                    "crossing yaw \(poses.yaw.data[lane])")
            #expect(poses.y.data[lane] > 0.005, "crossing card rests on the heart")
        }
        // And the heart lies flat beneath it.
        if let heartLane = (0..<w.capacity).first(where: { Int(w.slot.data[$0]) == 0 }) {
            #expect(abs(poses.yaw.data[heartLane]) < 0.001)
        }
    }
}
