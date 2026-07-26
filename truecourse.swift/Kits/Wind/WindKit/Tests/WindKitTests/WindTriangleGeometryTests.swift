import Testing
import Foundation
@testable import WindKit

// Oracle = the wind triangle must *draw* what it computes. For any solved leg, the diagram's
// three screen vectors must recover the physics: the track vector = course/GS, the air vector =
// heading/TAS, and the wind vector (track − air) must point toward `windFrom + 180` at
// `windSpeed`. And it must close: air + wind == track. This verifies the DISPLAY geometry
// (the canvas' bearing→screen mapping and y-flip), independent of the numeric solution.
@Suite("Wind — triangle diagram geometry")
struct WindTriangleGeometryTests {

    /// Smallest signed angular difference in degrees (handles 359↔1 wrap).
    private func angleDiff(_ a: Double, _ b: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }; if d < -180 { d += 360 }
        return abs(d)
    }

    private struct Case { let course, tas, windDir, windSpeed: Double; let name: String }

    private let cases = [
        Case(course: 90,  tas: 120, windDir: 180, windSpeed: 30, name: "quartering (default)"),
        Case(course: 360, tas: 100, windDir: 360, windSpeed: 20, name: "direct headwind"),
        Case(course: 360, tas: 100, windDir: 180, windSpeed: 20, name: "direct tailwind"),
        Case(course: 360, tas: 100, windDir: 90,  windSpeed: 25, name: "crosswind from right"),
        Case(course: 45,  tas: 140, windDir: 300, windSpeed: 42, name: "NW quartering"),
        Case(course: 270, tas: 95,  windDir: 20,  windSpeed: 15, name: "westbound, NE wind"),
    ]

    @Test func drawnTriangleRecoversPhysicsAndCloses() {
        for c in cases {
            guard let s = Wind.solution(courseDeg: c.course, tasKt: c.tas,
                                        windDirDeg: c.windDir, windSpeedKt: c.windSpeed) else {
                Issue.record("\(c.name): expected a solvable leg"); continue
            }
            let tri = Wind.triangle(courseDeg: c.course, tasKt: c.tas,
                                    headingDeg: s.headingDeg, gsKt: s.gsKt)

            // Track vector = course / groundspeed
            #expect(angleDiff(tri.track.bearingDeg, c.course) < 1e-6, "\(c.name): track bearing")
            #expect(abs(tri.track.magnitude - s.gsKt) < 1e-6, "\(c.name): track magnitude = GS")

            // Air vector = heading / TAS
            #expect(angleDiff(tri.air.bearingDeg, s.headingDeg) < 1e-6, "\(c.name): air bearing")
            #expect(abs(tri.air.magnitude - c.tas) < 1e-6, "\(c.name): air magnitude = TAS")

            // Wind vector recovers the wind: magnitude = windSpeed, points TOWARD windDir+180.
            #expect(abs(tri.wind.magnitude - c.windSpeed) < 1e-6, "\(c.name): wind magnitude")
            if c.windSpeed > 1e-6 {
                let towardExpected = (c.windDir + 180).truncatingRemainder(dividingBy: 360)
                #expect(angleDiff(tri.wind.bearingDeg, towardExpected) < 1e-6,
                        "\(c.name): wind points toward windDir+180")
            }

            // Closure: air + wind == track (the triangle actually closes).
            #expect(abs((tri.air.x + tri.wind.x) - tri.track.x) < 1e-9, "\(c.name): closure x")
            #expect(abs((tri.air.y + tri.wind.y) - tri.track.y) < 1e-9, "\(c.name): closure y")
        }
    }

    /// Sanity on the screen convention itself: north points up, east points right.
    @Test func screenConventionNorthUpEastRight() {
        let north = Wind.Vec2(x: 0, y: -1)   // straight up
        let east  = Wind.Vec2(x: 1, y: 0)    // right
        #expect(angleDiff(north.bearingDeg, 0) < 1e-9)
        #expect(angleDiff(east.bearingDeg, 90) < 1e-9)
    }
}
