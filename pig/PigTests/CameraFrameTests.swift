import XCTest
import simd
@testable import Pig

/// Which way is right.
///
/// The first build had the strafe axis negated: `D` moved the pig to the left of the screen. Nothing
/// caught it because both halves were internally consistent — the renderer placed the eye from one
/// formula and the input mapped the stick with another, and neither was checkable on its own.
///
/// So these tests do not compare formulas. They **project a point through the real view-projection
/// matrix and look at which side of the screen it lands on**, which is the question the player is
/// actually asking.
final class CameraFrameTests: XCTestCase {

    private let yaws: [Float] = [0, 0.7, 1.5708, 2.4, 3.1415, -0.9, -2.2, 5.9]

    /// Screen-right on the ground is `cross(forward, up)`. Stated as the cross product here so the
    /// closed form in `CameraFrame` has something independent to agree with.
    func testRightIsTheCrossProductOfForwardAndUp() {
        for yaw in yaws {
            let f2 = CameraFrame.forward(yaw: yaw)
            let f = SIMD3<Float>(f2.x, 0, f2.y)
            let expected = cross(f, SIMD3<Float>(0, 1, 0))
            let r2 = CameraFrame.right(yaw: yaw)
            XCTAssertEqual(r2.x, expected.x, accuracy: 1e-6, "right.x wrong at yaw \(yaw)")
            XCTAssertEqual(r2.y, expected.z, accuracy: 1e-6, "right.z wrong at yaw \(yaw)")
        }
    }

    func testForwardAndRightAreUnitAndPerpendicular() {
        for yaw in yaws {
            let f = CameraFrame.forward(yaw: yaw), r = CameraFrame.right(yaw: yaw)
            XCTAssertEqual(length(f), 1, accuracy: 1e-6)
            XCTAssertEqual(length(r), 1, accuracy: 1e-6)
            XCTAssertEqual(dot(f, r), 0, accuracy: 1e-6, "the basis is not orthogonal at yaw \(yaw)")
        }
    }

    /// **The one that matters.** Push the pig along `right` and it must appear on the right-hand side
    /// of the frame; along `forward` and it must move away from the camera, not toward it.
    func testTheBasisAgreesWithWhatEndsUpOnScreen() {
        let focus = SIMD3<Float>(3, 0.5, -2)
        for yaw in yaws {
            let eye = CameraFrame.eye(focus: focus, yaw: yaw, pitch: 0.36, distance: 4)
            let view = float4x4(lookAt: eye, target: focus, up: SIMD3<Float>(0, 1, 0))
            let proj = float4x4(perspectiveFOV: 58 * .pi / 180, aspect: 1.7, near: 0.05, far: 200)
            let vp = proj * view

            func ndc(_ p: SIMD3<Float>) -> SIMD3<Float> {
                let c = vp * SIMD4<Float>(p.x, p.y, p.z, 1)
                return SIMD3(c.x / c.w, c.y / c.w, c.z / c.w)
            }

            let r = CameraFrame.right(yaw: yaw), f = CameraFrame.forward(yaw: yaw)
            let toRight = focus + SIMD3(r.x, 0, r.y)
            let toLeft = focus - SIMD3(r.x, 0, r.y)
            let ahead = focus + SIMD3(f.x, 0, f.y)

            XCTAssertGreaterThan(ndc(toRight).x, 0.05,
                                 "a step along `right` did not land on the right of the screen "
                                 + "at yaw \(yaw)")
            XCTAssertLessThan(ndc(toLeft).x, -0.05, "…and its mirror did not land on the left")
            XCTAssertEqual(ndc(ahead).x, 0, accuracy: 0.05,
                           "a step along `forward` drifted sideways at yaw \(yaw)")
            XCTAssertGreaterThan(distance(ahead, eye), distance(focus, eye),
                                 "`forward` points toward the camera at yaw \(yaw)")
            XCTAssertGreaterThan(ndc(focus + SIMD3<Float>(0, 1, 0)).y, 0.05,
                                 "up is not up at yaw \(yaw)")
        }
    }

    /// The eye sits behind the subject along `forward`, and the pitch raises it.
    func testTheEyeSitsBehindAndAbove() {
        let focus = SIMD3<Float>(0, 0.5, 0)
        for yaw in yaws {
            let low = CameraFrame.eye(focus: focus, yaw: yaw, pitch: 0.1, distance: 4)
            let high = CameraFrame.eye(focus: focus, yaw: yaw, pitch: 0.8, distance: 4)
            XCTAssertGreaterThan(high.y, low.y, "more pitch must mean a higher camera")
            XCTAssertEqual(distance(low, focus), 4, accuracy: 1e-5, "distance is not the distance")

            let f = CameraFrame.forward(yaw: yaw)
            let behind = SIMD2(low.x - focus.x, low.z - focus.z)
            XCTAssertLessThan(dot(normalize(behind), f), -0.9,
                              "the camera is not behind the subject at yaw \(yaw)")
        }
    }

    /// Turning is always taken the short way round, including across the ±π seam — which is where a
    /// camera that trails the player would otherwise spin the long way for no reason.
    func testTheShortestTurnIsActuallyTheShortest() {
        let pi = Float.pi
        XCTAssertEqual(CameraFrame.shortestTurn(from: 3.0, to: -3.0), 0.2831, accuracy: 1e-3)
        XCTAssertEqual(CameraFrame.shortestTurn(from: -3.0, to: 3.0), -0.2831, accuracy: 1e-3)
        XCTAssertEqual(CameraFrame.shortestTurn(from: 0, to: 0.5), 0.5, accuracy: 1e-6)
        for a in stride(from: -8.0 as Float, through: 8.0, by: 0.37) {
            for b in stride(from: -8.0 as Float, through: 8.0, by: 0.41) {
                let d = CameraFrame.shortestTurn(from: a, to: b)
                XCTAssertLessThanOrEqual(abs(d), pi + 1e-5, "took the long way from \(a) to \(b)")
            }
        }
    }
}
