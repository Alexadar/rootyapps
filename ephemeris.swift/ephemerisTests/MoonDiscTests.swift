import Testing
import Foundation
import SwiftUI
import EphemerisKit
@testable import Ephemeris

/// The hemisphere rule and the terminator geometry.
///
/// Drawing the Moon lit on the wrong side is the most frequently reported defect in this category
/// of app: half the planet can check it by looking out of the window. It is also invisible to the
/// person who wrote it, because they almost certainly live in one hemisphere and it looks right
/// there.
///
/// `litOnRight` is a free function precisely so the rule can be asserted without rendering, and the
/// four cases below are the entire rule.
@Suite("Moon disc")
struct MoonDiscTests {

    // MARK: - Hemisphere

    /// Waxing is lit on the right in the north and on the left in the south. Waning reverses both.
    @Test func theFourHemisphereCasesAreCorrect() {
        let london = 51.5, sydney = -33.9

        #expect(litOnRight(waxing: true,  latitude: london) == true,
                "a northern waxing Moon is lit on the right")
        #expect(litOnRight(waxing: false, latitude: london) == false,
                "a northern waning Moon is lit on the left")
        #expect(litOnRight(waxing: true,  latitude: sydney) == false,
                "a southern waxing Moon is lit on the LEFT — this is the defect users report")
        #expect(litOnRight(waxing: false, latitude: sydney) == true,
                "a southern waning Moon is lit on the right")
    }

    /// Every southern latitude must mirror its northern counterpart, not just the one city above.
    /// A rule written as `latitude < -23` or similar would pass the spot check and fail here.
    @Test func everySouthernLatitudeMirrorsItsNorthernCounterpart() {
        for magnitude in stride(from: 0.5, through: 89.5, by: 1.0) {
            for waxing in [true, false] {
                let north = litOnRight(waxing: waxing, latitude: magnitude)
                let south = litOnRight(waxing: waxing, latitude: -magnitude)
                #expect(north != south,
                        "±\(magnitude)° waxing=\(waxing) gave the same handedness on both sides")
            }
        }
    }

    // MARK: - Terminator geometry

    /// The lit area must track the illuminated fraction: nothing at new, half at the quarters,
    /// everything at full — and monotonically in between.
    ///
    /// Measured by sampling the path rather than trusting the control points, because the failure
    /// mode of a Bézier terminator is a shape that is *plausible* and wrong.
    @Test func litAreaTracksIlluminationFromNewToFull() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)

        func litFraction(_ k: Double, litOnRight: Bool = true) -> Double {
            let path = MoonDisc(illumination: k, litOnRight: litOnRight).path(in: rect).cgPath
            // Sample the disc on a grid and count what falls inside the lit path.
            var inside = 0, total = 0
            for xi in stride(from: 0.5, to: 100, by: 1.0) {
                for yi in stride(from: 0.5, to: 100, by: 1.0) {
                    let p = CGPoint(x: xi, y: yi)
                    // Only points on the lunar disc itself count toward the denominator.
                    let dx = xi - 50, dy = yi - 50
                    guard dx * dx + dy * dy <= 50 * 50 else { continue }
                    total += 1
                    if path.contains(p) { inside += 1 }
                }
            }
            return Double(inside) / Double(total)
        }

        // The Bézier half-ellipse is an approximation, so allow a couple of percent.
        #expect(litFraction(0.0) < 0.02, "new moon should be dark, got \(litFraction(0.0))")
        #expect(litFraction(1.0) > 0.98, "full moon should be lit, got \(litFraction(1.0))")
        #expect(abs(litFraction(0.5) - 0.5) < 0.03, "quarter should be half, got \(litFraction(0.5))")

        var previous = -1.0
        for k in stride(from: 0.0, through: 1.0, by: 0.1) {
            let f = litFraction(k)
            #expect(f >= previous - 0.02, "lit area went backwards at k=\(k): \(f) after \(previous)")
            #expect(abs(f - k) < 0.05, "k=\(k) drew \(String(format: "%.3f", f)) of the disc")
            previous = f
        }
    }

    /// The mirror really mirrors: a left-lit crescent is the right-lit one reflected, so the two
    /// cover the same amount of disc and sit on opposite sides of the centre line.
    @Test func mirroringChangesTheSideButNotTheAmount() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)

        for k in [0.15, 0.35, 0.65, 0.85] {
            let right = MoonDisc(illumination: k, litOnRight: true).path(in: rect).cgPath
            let left = MoonDisc(illumination: k, litOnRight: false).path(in: rect).cgPath

            func mass(_ path: CGPath) -> (count: Int, meanX: Double) {
                var n = 0, sum = 0.0
                for xi in stride(from: 0.5, to: 100, by: 1.0) {
                    for yi in stride(from: 0.5, to: 100, by: 1.0) {
                        if path.contains(CGPoint(x: xi, y: yi)) { n += 1; sum += xi }
                    }
                }
                return (n, n == 0 ? 50 : sum / Double(n))
            }

            let r = mass(right), l = mass(left)
            #expect(abs(Double(r.count - l.count)) < Double(r.count) * 0.02,
                    "k=\(k): mirrored areas differ, \(r.count) vs \(l.count)")
            // Centres of mass sit symmetrically about x = 50.
            #expect(abs((r.meanX - 50) + (l.meanX - 50)) < 1.5,
                    "k=\(k): centres at \(r.meanX) and \(l.meanX) are not symmetric about 50")
        }
    }

    /// Out-of-range input must clamp rather than produce a path that escapes the disc — the Kit
    /// clamps illumination too, but a view should not depend on its caller to be careful.
    @Test func illuminationOutsideZeroToOneClamps() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        for k in [-1.0, -0.2, 1.2, 5.0] {
            let box = MoonDisc(illumination: k, litOnRight: true).path(in: rect).boundingRect
            #expect(rect.insetBy(dx: -1, dy: -1).contains(box),
                    "illumination \(k) drew outside the disc: \(box)")
        }
    }
}
