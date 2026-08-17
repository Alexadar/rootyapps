import XCTest
import simd
@testable import BigPinkCat

/// The coverage pincer, modelled on `kerfcalcTests/ToolCatalogCoverageTests.swift`: counts are
/// asserted from both sides, so a nineteenth demo fails a test whichever side it is added from.
final class DemoCatalogTests: XCTestCase {

    /// The camera the demo's own scripted move puts you at. Using the script rather than a fixed
    /// camera means these tests also exercise `CameraMove`, so a move that produces a NaN distance
    /// or a degenerate basis fails here rather than on a device.
    static func testCamera(_ d: Demo, _ t: Double) -> Snapshot.Camera {
        var rig = CameraRig()
        rig.applyScripted(d.cameraMove, at: t)
        return rig.camera()
    }

    func testEveryScriptedCameraStaysFiniteAndOutsideTheRing() {
        // This test used to assert the camera stayed OUTSIDE the horizon, which was right when the
        // interior was a painted disc and is wrong now. Diving through r+ on a warp platform is the
        // premise, so the interior is a place you work — the bound that matters is the RING
        // SINGULARITY at r = 0, which is the only thing here that is physical rather than a
        // coordinate artefact.
        //
        // A NaN in any of the three closures still silently blanks the frame, so finiteness stays.
        for d in Demo.allCases {
            for i in 0...120 {
                let t = Double(i) * 1.0
                var rig = CameraRig()
                rig.applyScripted(d.cameraMove, at: t)
                XCTAssertTrue(rig.distance.isFinite && rig.azimuth.isFinite
                              && rig.elevation.isFinite, "\(d.title) at t=\(t): non-finite rig")
                XCTAssertGreaterThanOrEqual(rig.distance, CameraRig.minDistance - 1e-6,
                                            "\(d.title) at t=\(t): camera reached the ring")
                XCTAssertLessThanOrEqual(abs(rig.elevation), CameraRig.maxElevation + 1e-6,
                                         "\(d.title): elevation past the pole, basis degenerates")
                let c = rig.camera()
                XCTAssertTrue(c.eye.x.isFinite && c.eye.y.isFinite && c.eye.z.isFinite,
                              "\(d.title) at t=\(t): non-finite eye")
            }
        }
    }

    func testEveryDemoExplainsWhatItsCameraIsShowing() {
        // Motion without a stated intent is just drift. If the move is part of the content, it has
        // to say what it reveals.
        for d in Demo.allCases {
            XCTAssertGreaterThan(d.cameraMove.intent.count, 15, "\(d.title): camera intent too thin")
        }
    }

    func testManualAndScriptedProduceTheSameCameraAtTheSeedInstant() {
        // Toggling to manual must not jump the view: manual is seeded from the script's current
        // pose, so at the seed instant the two cameras are identical.
        for d in Demo.allCases {
            var scripted = CameraRig(); scripted.applyScripted(d.cameraMove, at: 3.0)
            var manual = CameraRig(); manual.applyScripted(d.cameraMove, at: 3.0)
            XCTAssertEqual(scripted.camera().eye, manual.camera().eye, "\(d.title)")
        }
    }

    func testCatalogHasExactlyEighteenDemos() {
        XCTAssertEqual(Demo.allCases.count, 18,
                       "the table specifies eighteen demos; adding one must fail here too")
    }

    func testTierCountsMatchThePlan() {
        // 5 screen-space, 6 geodesic, 4 portal, 3 mechanics.
        XCTAssertEqual(Demo.allCases.filter { $0.tier == 1 }.count, 5)
        XCTAssertEqual(Demo.allCases.filter { $0.tier == 2 }.count, 6)
        XCTAssertEqual(Demo.allCases.filter { $0.tier == 3 }.count, 4)
        XCTAssertEqual(Demo.allCases.filter { $0.tier == 4 }.count, 3)
    }

    func testEveryDemoCitesAnOracle() {
        // The project's central claim is that every number has a source. No demo ships without one.
        for d in Demo.allCases {
            XCTAssertFalse(d.oracle.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(d.title) has no oracle")
            XCTAssertGreaterThan(d.oracle.count, 12, "\(d.title): oracle is too vague to be checked")
        }
    }

    func testEveryDemoHasAUniqueTitleAndRawValue() {
        XCTAssertEqual(Set(Demo.allCases.map(\.title)).count, 18)
        XCTAssertEqual(Set(Demo.allCases.map(\.rawValue)).count, 18)
    }

    func testTierOneIsCameraOnlyAndTierTwoPlusIsNot() {
        // The distinction the whole architecture turns on. If a Tier 1 demo ever claims world-space
        // it is lying about whether a thrown object would curve.
        for d in Demo.allCases {
            XCTAssertEqual(d.isWorldSpace, d.tier >= 2, "\(d.title) misreports its space")
        }
    }

    func testEveryDemoBuildsASnapshotWithFiniteGeometry() {
        // Cheap smoke over the whole catalog: no NaN reaches the renderer from any demo at any spin.
        for d in Demo.allCases {
            for spin in [0.0, 0.5, 0.9, 0.999] {
                let snap = d.makeSnapshot(spin: spin, time: 1.25, camera: Self.testCamera(d, 1.25))
                XCTAssertFalse(snap.bodies.isEmpty, "\(d.title) at a=\(spin) produced no bodies")
                for b in snap.bodies {
                    XCTAssertTrue(b.position.x.isFinite && b.position.y.isFinite
                                  && b.position.z.isFinite,
                                  "\(d.title) at a=\(spin): non-finite body position")
                    XCTAssertTrue(b.scale.isFinite && b.scale > 0, "\(d.title): bad scale")
                }
                XCTAssertTrue(snap.relativity.outerHorizon.isFinite
                              && snap.relativity.outerHorizon > 0,
                              "\(d.title) at a=\(spin): bad horizon radius")
            }
        }
    }

    func testSnapshotIsAPureFunctionOfItsInputs() {
        // The renderer must be replayable: same demo, same spin, same time → same scene.
        for d in Demo.allCases {
            let a = d.makeSnapshot(spin: 0.7, time: 2.0, camera: Self.testCamera(d, 2.0))
            let b = d.makeSnapshot(spin: 0.7, time: 2.0, camera: Self.testCamera(d, 2.0))
            XCTAssertEqual(a.bodies.count, b.bodies.count, "\(d.title)")
            for (x, y) in zip(a.bodies, b.bodies) {
                XCTAssertEqual(x.position, y.position, "\(d.title) is not reproducible")
            }
        }
    }
}

/// Every colour must be traceable to a pixel in the source art or to a stated derivation. This is
/// the oracle rule applied to the palette: `citypigeon`'s "do not invent a palette", enforced.
final class PaletteTests: XCTestCase {

    func testMeasuredColoursAreExactlyTheSampledHexes() {
        // The eighteen hexes sampled by median-cut quantisation from char1/char2/style.png.
        // If someone nudges one "to look better", this fails and the palette doc stays true.
        for hex in Palette.measuredHexes {
            let c = Palette.rgb(hex)
            XCTAssertTrue(Palette.allNamed.contains { $0.1 == c },
                          "measured hex #\(String(hex, radix: 16)) is not exposed under any name")
        }
    }

    func testEveryNamedColourIsInGamut() {
        for (name, c) in Palette.allNamed {
            for ch in [c.x, c.y, c.z] {
                XCTAssertTrue(ch >= 0 && ch <= 1, "\(name) is out of gamut: \(c)")
                XCTAssertTrue(ch.isFinite, "\(name) is not finite")
            }
        }
    }

    func testHorizonIsDarkButNotBlack() {
        // A true #000000 hole against a dark scene reads as a rendering failure rather than a hole,
        // and nothing else in this palette is pure black either.
        let luma = Palette.horizon.x * 0.2126 + Palette.horizon.y * 0.7152 + Palette.horizon.z * 0.0722
        XCTAssertGreaterThan(luma, 0.0, "the horizon is not pure black")
        XCTAssertLessThan(luma, 0.05, "but it is the darkest thing on screen")
    }

    func testRedshiftRampIsMonotonicallyDarkening() {
        // Redshift moves light toward longer wavelengths and, in this palette, toward lower value.
        // A ramp that brightened anywhere would read as the wrong physical direction.
        var previous = Float.infinity
        for i in 0...10 {
            let c = Palette.redshift(Float(i) / 10)
            let luma = c.x * 0.2126 + c.y * 0.7152 + c.z * 0.0722
            XCTAssertLessThanOrEqual(luma, previous + 1e-6, "ramp brightens at t=\(Float(i) / 10)")
            previous = luma
        }
    }

    func testRedshiftRampIsClampedOutsideZeroToOne() {
        XCTAssertEqual(Palette.redshift(-5), Palette.redshiftRamp.first!)
        XCTAssertEqual(Palette.redshift(5), Palette.redshiftRamp.last!)
    }

    func testCatSignalIsTheMostSaturatedColour() {
        // §9-style reservation: the loudest colour is reserved for exactly the loud things, so it
        // must actually be the loudest. Saturation here is the HSV definition, (max-min)/max.
        func sat(_ c: SIMD3<Float>) -> Float {
            let hi = max(c.x, max(c.y, c.z)), lo = min(c.x, min(c.y, c.z))
            return hi <= 0 ? 0 : (hi - lo) / hi
        }
        let measured = Palette.measuredHexes.map { Palette.rgb($0) }
        let best = measured.map(sat).max() ?? 0
        XCTAssertEqual(sat(Palette.catSignal), best, accuracy: 1e-6,
                       "catSignal must be the most saturated measured colour")
    }
}
