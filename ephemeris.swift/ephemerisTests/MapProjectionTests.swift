import Testing
import Foundation
import CoreGraphics
import EphemerisKit
@testable import Ephemeris

/// The equirectangular projection, and the seam.
///
/// The load-bearing test is `aLineCrossingTheDatelineIsSplit`. A path that runs off the right edge
/// at +180° reappears at −180°, and joining the two ends draws a horizontal stroke straight across
/// the entire map — a line that exists nowhere on Earth. It is easy to write, invisible in the
/// hemisphere you happen to look at, and obvious the moment someone pans east.
@Suite("Map projection")
struct MapProjectionTests {

    // MARK: - Placement

    @Test func theCornersAndCentreLandWhereTheyShould() {
        // x runs west→east, y runs north→south.
        let nw = MapProjection.unitPoint(latitude: 90, longitude: -180)
        let se = MapProjection.unitPoint(latitude: -90, longitude: 180)
        let centre = MapProjection.unitPoint(latitude: 0, longitude: 0)

        #expect(abs(nw.x - 0) < 1e-9 && abs(nw.y - 0) < 1e-9, "NW corner at \(nw)")
        #expect(abs(se.x - 1) < 1e-9 && abs(se.y - 1) < 1e-9, "SE corner at \(se)")
        #expect(abs(centre.x - 0.5) < 1e-9 && abs(centre.y - 0.5) < 1e-9, "0,0 at \(centre)")
    }

    /// Known cities, so the projection is checked against geography rather than against itself.
    @Test func knownCitiesLandInTheRightQuadrant() {
        let london = MapProjection.unitPoint(latitude: 51.5, longitude: -0.13)
        let sydney = MapProjection.unitPoint(latitude: -33.9, longitude: 151.2)
        let quito  = MapProjection.unitPoint(latitude: -0.18, longitude: -78.5)

        #expect(london.x < 0.5 && london.y < 0.5, "London is north-west of centre: \(london)")
        #expect(sydney.x > 0.5 && sydney.y > 0.5, "Sydney is south-east of centre: \(sydney)")
        #expect(quito.x < 0.5, "Quito is west of Greenwich")
        #expect(abs(quito.y - 0.5) < 0.01, "Quito is on the equator, y = \(quito.y)")
    }

    /// Nothing may escape the unit square, whatever it is handed — a point drawn outside the map
    /// rect shows as a stray mark over the surrounding UI.
    @Test func everyInputStaysInsideTheUnitSquare() {
        for lat in stride(from: -400.0, through: 400.0, by: 17) {
            for lon in stride(from: -900.0, through: 900.0, by: 37) {
                let p = MapProjection.unitPoint(latitude: lat, longitude: lon)
                #expect(p.x >= 0 && p.x <= 1, "x \(p.x) for lon \(lon)")
                #expect(p.y >= 0 && p.y <= 1, "y \(p.y) for lat \(lat)")
            }
        }
    }

    @Test func longitudeWrapsIntoTheHalfOpenRange() {
        #expect(MapProjection.wrapLongitude(0) == 0)
        #expect(MapProjection.wrapLongitude(190) == -170)
        #expect(MapProjection.wrapLongitude(-190) == 170)
        #expect(MapProjection.wrapLongitude(540) == 180)
        // Both ends stay put: they are the same meridian but opposite edges of the map, and a
        // coastline ring touching the dateline needs each of them.
        #expect(MapProjection.wrapLongitude(180) == 180, "180 must not become -180")
        #expect(MapProjection.wrapLongitude(-180) == -180, "-180 must not become 180")
    }

    // MARK: - The seam

    @Test func aLineCrossingTheDatelineIsSplit() {
        // Walks east across the dateline: 170 → 180 → −170.
        let points: [(latitude: Double, longitude: Double)] = [
            (10, 170), (10, 175), (10, 179), (10, -179), (10, -175), (10, -170),
        ]
        let runs = MapProjection.segments(points)

        #expect(runs.count == 2, "expected two runs across the seam, got \(runs.count)")
        // And neither run may span the map: that is the artefact being prevented.
        for run in runs {
            let width = (run.map(\.x).max() ?? 0) - (run.map(\.x).min() ?? 0)
            #expect(width < 0.5, "a run spans \(width) of the map — the seam was joined")
        }
    }

    @Test func aLineThatNeverCrossesStaysOneRun() {
        let points = stride(from: -60.0, through: 60.0, by: 5).map {
            (latitude: $0, longitude: 12.0)
        }
        #expect(MapProjection.segments(points).count == 1)
    }

    /// Degenerate input must not produce a one-point "run", which draws as nothing but costs a
    /// path move and can trip a `first!` somewhere downstream.
    @Test func emptyAndSinglePointInputProduceNoRuns() {
        #expect(MapProjection.segments([]).isEmpty)
        #expect(MapProjection.segments([(0, 0)]).isEmpty)
    }

    @Test func placeScalesIntoTheTargetRect() {
        let rect = CGRect(x: 10, y: 20, width: 200, height: 100)
        let p = MapProjection.place(CGPoint(x: 0.5, y: 0.25), in: rect)
        #expect(abs(p.x - 110) < 1e-9 && abs(p.y - 45) < 1e-9, "placed at \(p)")
    }

    // MARK: - Distance

    /// Checked against published great-circle distances, so this is external ground truth rather
    /// than the formula agreeing with itself.
    @Test func haversineMatchesPublishedCityDistances() {
        let cases: [(String, (Double, Double), (Double, Double), Double)] = [
            ("London–Paris",   (51.5074, -0.1278), (48.8566, 2.3522),   344),
            ("London–NewYork", (51.5074, -0.1278), (40.7128, -74.0060), 5570),
            ("Sydney–Tokyo",   (-33.8688, 151.2093), (35.6762, 139.6503), 7823),
        ]
        for (name, a, b, expected) in cases {
            let d = GeoDistance.kilometres(from: (a.0, a.1), to: (b.0, b.1))
            let error = abs(d - expected) / expected
            #expect(error < 0.01, "\(name): got \(Int(d)) km, published \(Int(expected)) km")
        }
    }

    @Test func aPointIsZeroKilometresFromItself() {
        #expect(GeoDistance.kilometres(from: (51.5, -0.13), to: (51.5, -0.13)) < 1e-9)
    }

    /// East/west must respect the seam: a point at −179° is two degrees EAST of +179°, not most of
    /// a world west of it.
    @Test func directionIsCorrectAcrossTheDateline() {
        #expect(GeoDistance.isEast(of: 179, point: -179), "−179 is just east of +179")
        #expect(!GeoDistance.isEast(of: -179, point: 179), "+179 is just west of −179")
        #expect(GeoDistance.isEast(of: 0, point: 10))
        #expect(!GeoDistance.isEast(of: 0, point: -10))
    }

    // MARK: - The bundled coastline

    /// The asset is real data, not decoration: if it fails to load the map silently loses its only
    /// frame of reference and the lines float over a blank rectangle.
    @Test func theCoastlineAssetLoadsAndIsPlausible() {
        let rings = CoastlineAtlas.rings
        #expect(rings.count > 50, "only \(rings.count) coastline rings — asset missing or truncated?")

        var points = 0
        for ring in rings {
            #expect(ring.count >= 4, "a ring with \(ring.count) points is not a polygon")
            for pair in ring {
                #expect(pair.count == 2, "coordinate pair has \(pair.count) values")
                #expect(pair[0] >= -180 && pair[0] <= 180, "longitude \(pair[0]) out of range")
                #expect(pair[1] >= -90 && pair[1] <= 90, "latitude \(pair[1]) out of range")
                points += 1
            }
        }
        #expect(points > 2000, "only \(points) coastline points")
    }
}
