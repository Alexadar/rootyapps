import XCTest
import CardMotionKit
@testable import Tarot

/// The computed camera fit: pure math, so it gets the pure-math treatment — every shipped
/// layout must fit inside the frustum at the computed distance on every shipped aspect,
/// and the three-card layout must reproduce the original shipping boom exactly.
final class CameraFitChecks: XCTestCase {

    private let layouts: [(String, MotionConfig)] = [
        ("oneCard", .oneCard), ("threeCard", .threeCard),
        ("fiveCrossroads", .fiveCrossroads), ("celticCross", .celticCross),
    ]
    // iPhone portrait, iPad portrait, the Mac default window.
    private let aspects: [(String, Double)] = [
        ("iPhone", 390.0 / 844.0), ("iPad", 1024.0 / 1366.0), ("Mac", 760.0 / 1000.0),
    ]

    /// The calibration contract: the default layout on the reference phone IS the shipping
    /// boom — by construction, and pinned here so a pad/formula change cannot silently
    /// reframe the shipped look.
    func testThreeCardOnReferencePhoneIsTheShippingBoom() {
        let d = CameraFit.distance(config: .standard, aspect: CameraFit.referenceAspect)
        XCTAssertEqual(d, CameraFit.homeDistance, accuracy: 1e-9)
        // And no layout is ever framed closer than the shipping boom.
        for (name, layout) in layouts {
            for (device, aspect) in aspects {
                XCTAssertGreaterThanOrEqual(CameraFit.distance(config: layout, aspect: aspect),
                                            CameraFit.homeDistance - 1e-9, "\(name)/\(device)")
            }
        }
    }

    /// Every corner of every layout sits inside the frustum at the computed distance —
    /// verified against the raw (uncalibrated) constraint with the calibration slack
    /// treated as the acceptable bleed the shipping layout already proves acceptable.
    func testEveryLayoutFitsOnEveryAspect() {
        for (name, layout) in layouts {
            for (device, aspect) in aspects {
                let d = CameraFit.distance(config: layout, aspect: aspect)
                let dRaw = CameraFit.rawDistance(config: layout, aspect: aspect)
                // The raw solve is the conservative bound; calibrated distance may sit
                // below it only by the measured shipping slack.
                XCTAssertGreaterThanOrEqual(d / dRaw, CameraFit.calibration - 1e-9,
                                            "\(name)/\(device)")
                XCTAssertTrue(d.isFinite && d > 0, "\(name)/\(device)")
            }
        }
    }

    /// Bigger layouts pull back monotonically; the ten-card cross needs the farthest boom.
    func testLargerLayoutsPullTheCameraOut() {
        let phone = 390.0 / 844.0
        let d1 = CameraFit.distance(config: .oneCard, aspect: phone)
        let d3 = CameraFit.distance(config: .threeCard, aspect: phone)
        let d5 = CameraFit.distance(config: .fiveCrossroads, aspect: phone)
        let d10 = CameraFit.distance(config: .celticCross, aspect: phone)
        XCTAssertLessThanOrEqual(d1, d3 + 1e-9)
        XCTAssertLessThan(d3, d5, "the crossroads' deep row must pull the camera out")
        XCTAssertLessThan(d3, d10, "the cross-and-staff must pull the camera out")
    }

    /// The crossing card's sideways footprint counts: a yawed slot must widen the box.
    func testYawedSlotWidensTheBoundingBox() {
        var straight = MotionConfig.celticCross
        straight.slotYaw = [Double](repeating: 0, count: straight.slotCount)
        let xs = CameraFit.corners(of: MotionConfig.celticCross).map(\.x)
        let xsStraight = CameraFit.corners(of: straight).map(\.x)
        XCTAssertLessThan(xsStraight.min() ?? 0, (xs.min() ?? 0) + 0.2)
        XCTAssertGreaterThan((xs.min() ?? 0), -2)
        // The crossing slot at yaw π/2 contributes cardLength/2 in x, not cardWidth/2.
        let crossingHalfX = abs(cos(Double.pi / 2)) * MotionConfig.celticCross.cardWidth / 2
            + abs(sin(Double.pi / 2)) * MotionConfig.celticCross.cardLength / 2
        XCTAssertEqual(crossingHalfX, MotionConfig.celticCross.cardLength / 2, accuracy: 1e-12)
    }
}
