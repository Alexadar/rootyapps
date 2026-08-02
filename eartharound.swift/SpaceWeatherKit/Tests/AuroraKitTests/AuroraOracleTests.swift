import Testing
import Foundation
@testable import AuroraKit

/// ORACLE = NOAA SWPC aurora "Kp → geomagnetic latitude" view-line table.
///
///   Kp:  0     1     2     3     4     5     6     7     8     9
///   lat: 66.5  64.5  62.4  60.4  58.3  56.3  54.2  52.2  50.1  48.1   (° geomagnetic)
///
///   Source: NOAA SWPC aurora tutorial / "Aurora — 30 Minute Forecast" Kp-to-latitude
///           correspondence. Latitudes are geomagnetic; higher Kp pushes the oval equatorward.
@Suite("Aurora oracle — NOAA Kp→latitude view line")
struct AuroraOracleTests {

    static let oracle: [Double] = [66.5, 64.5, 62.4, 60.4, 58.3, 56.3, 54.2, 52.2, 50.1, 48.1]

    @Test func tableMatchesNOAA() {
        #expect(Aurora.latitudeByKp == Self.oracle)
        for kp in 0...9 {
            #expect(Aurora.equatorwardGeomagLatitude(kp: Double(kp)) == Self.oracle[kp], "Kp \(kp)")
        }
    }

    @Test func higherKpMovesOvalEquatorward() {
        var prev = 999.0
        for kp in 0...9 {
            let lat = Aurora.equatorwardGeomagLatitude(kp: Double(kp))
            #expect(lat < prev, "Kp \(kp) should be lower latitude than \(kp - 1)")
            prev = lat
        }
    }

    @Test func fractionalKpInterpolates() {
        // Halfway between Kp5 (56.3) and Kp6 (54.2) = 55.25°.
        #expect(abs(Aurora.equatorwardGeomagLatitude(kp: 5.5) - 55.25) < 1e-9)
    }

    @Test func clampsOutOfRange() {
        #expect(Aurora.equatorwardGeomagLatitude(kp: -3) == 66.5)
        #expect(Aurora.equatorwardGeomagLatitude(kp: 12) == 48.1)
    }

    @Test func ovationGridReduction() {
        let cells = [
            Aurora.OvationCell(longitude: 10, latitude: 60, probability: 5),
            Aurora.OvationCell(longitude: 200, latitude: 70, probability: 82),
            Aurora.OvationCell(longitude: 359, latitude: 65, probability: 40),
        ]
        #expect(Aurora.maxProbability(in: cells) == 82)
        // Nearest to (lat 71, lon 199) is the 70/200 cell.
        #expect(Aurora.probability(atLatitude: 71, longitude: 199, in: cells) == 82)
        // Longitude wrap: lon 1 is nearer to the 359 cell than to the 10 cell.
        #expect(Aurora.probability(atLatitude: 65, longitude: 1, in: cells) == 40)
        #expect(Aurora.maxProbability(in: []) == 0)
    }
}
