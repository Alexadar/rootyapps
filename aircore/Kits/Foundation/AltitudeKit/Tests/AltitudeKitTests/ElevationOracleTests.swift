import Testing
import Foundation
@testable import AltitudeKit

/// Oracle: the **published standard-atmosphere table** (ASHRAE Fundamentals Ch. 1 Table 1), whose
/// barometric pressures are printed to five figures in psia. The equation this Kit implements is
/// the one that table is generated from, so agreement to the table's own precision is the bar.
@Suite("Standard atmosphere")
struct ElevationOracleTests {

    static let pascalsPerPSI = 6894.757293168

    struct TablePoint {
        let feet: Double
        /// Published barometric pressure, psia.
        let psia: Double
    }

    /// Published table values. Anchors chosen where the printed figure is unambiguous.
    static let published: [TablePoint] = [
        .init(feet: -1000, psia: 15.236),
        .init(feet: 0, psia: 14.696),
        .init(feet: 1000, psia: 14.175),
        .init(feet: 2000, psia: 13.664),
        .init(feet: 3000, psia: 13.171),
        .init(feet: 5000, psia: 12.228),
        .init(feet: 10000, psia: 10.108),
    ]

    @Test("Barometric pressure against the published table", arguments: published)
    func matchesPublishedTable(_ point: TablePoint) throws {
        let elevation = try Elevation(feet: point.feet)
        let psia = elevation.barometricPressure / Self.pascalsPerPSI
        #expect(abs(psia - point.psia) < 0.005,
                "at \(point.feet) ft: \(psia) psia vs published \(point.psia)")
    }

    @Test func seaLevelIsTheDefiningValue() {
        #expect(abs(Elevation.seaLevel.barometricPressure - 101_325) < 1e-9)
        #expect(abs(Elevation.seaLevel.pressureRatio - 1) < 1e-12)
        #expect(abs(Elevation.seaLevel.standardTemperature - 15) < 1e-12)
    }

    /// The number the altitude sheet exists to make visible: Denver runs at 82 % of sea-level
    /// pressure, which is where the trade's sea-level constants go 11 % wrong.
    @Test func denverAndMexicoCity() {
        #expect(abs(Elevation.denver.barometricPressure - 83_427.51) < 1.0)
        #expect(abs(Elevation.denver.pressureRatio - 0.8233) < 1e-4)
        #expect(abs(Elevation.denver.feet - 5280) < 1e-9)

        #expect(abs(Elevation.mexicoCity.barometricPressure - 77_151.95) < 1.0)
        #expect(abs(Elevation.mexicoCity.pressureRatio - 0.7614) < 1e-4)
    }

    @Test func pressureFallsMonotonicallyWithHeight() throws {
        var previous = Double.infinity
        for feet in stride(from: -1000.0, through: 15_000, by: 250) {
            let p = try Elevation(feet: feet).barometricPressure
            #expect(p < previous, "pressure rose between samples at \(feet) ft")
            previous = p
        }
    }

    @Test func standardTemperatureFollowsTheLapseRate() throws {
        // 15 °C at sea level, falling 6.5 °C per km.
        #expect(abs(try Elevation(metres: 1000).standardTemperature - 8.5) < 1e-9)
        #expect(abs(try Elevation(feet: 5000).standardTemperature - 5.094) < 1e-3)
    }

    @Test func metresAndFeetRoundTrip() throws {
        for feet in [-1000.0, 0, 1234.5, 5280, 10_000] {
            #expect(abs(try Elevation(feet: feet).feet - feet) < 1e-9)
        }
    }

    @Test func rejectsElevationsOutsideThePublishedRange() {
        #expect(throws: ElevationError.outOfRange(metres: 12_000)) {
            try Elevation(metres: 12_000)
        }
        #expect(throws: ElevationError.outOfRange(metres: -6_000)) {
            try Elevation(metres: -6_000)
        }
        #expect(throws: (any Error).self) { try Elevation(metres: .nan) }
        #expect(throws: (any Error).self) { try Elevation(feet: .infinity) }
    }

    @Test func elevationsRoundTripThroughCodable() throws {
        let elevation = try Elevation(feet: 5280)
        let back = try JSONDecoder().decode(Elevation.self,
                                            from: JSONEncoder().encode(elevation))
        #expect(back == elevation)
    }
}
