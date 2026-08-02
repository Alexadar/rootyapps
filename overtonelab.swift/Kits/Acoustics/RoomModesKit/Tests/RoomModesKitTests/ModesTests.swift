import Testing
import Foundation
@testable import RoomModesKit

// Oracle = the closed-form rectangular-room eigenfrequency f=(c/2)·√((nx/L)²+(ny/W)²+(nz/H)²)
// (Kuttruff / Everest — Master Handbook of Acoustics), the Bonello criterion (JAES 1981), and
// published Sepmeyer/Louden room ratios.
@Suite("Room modes")
struct ModesTests {
    let c = 343.0

    @Test func firstAxialMatchesClosedForm() {
        let ms = RoomModes.modes(lengthM: 5, widthM: 4, heightM: 2.8, speed: c, maxHz: 300)
        // (1,0,0) along L=5 → c/(2·5) = 34.3 Hz.
        let axL = ms.first { $0.nx == 1 && $0.ny == 0 && $0.nz == 0 }
        #expect(axL != nil)
        #expect(abs(axL!.hz - 34.3) < 1e-6)
        #expect(axL!.type == .axial)
    }

    @Test func tangentialWorkedValue() {
        let ms = RoomModes.modes(lengthM: 5, widthM: 4, heightM: 2.8, speed: c, maxHz: 300)
        // (1,1,0): (343/2)·√((1/5)²+(1/4)²) = 171.5·√0.1025 = 54.90679… Hz.
        let m = ms.first { $0.nx == 1 && $0.ny == 1 && $0.nz == 0 }
        #expect(m != nil)
        #expect(abs(m!.hz - 54.90679) < 1e-4)
        #expect(m!.type == .tangential)
    }

    @Test func obliqueAndOrdering() {
        let ms = RoomModes.modes(lengthM: 5, widthM: 4, heightM: 2.8, speed: c, maxHz: 300)
        #expect(ms.contains { $0.type == .oblique })            // some (nx,ny,nz all>0) exist ≤300
        for i in 1..<ms.count { #expect(ms[i].hz >= ms[i - 1].hz) }   // sorted ascending
    }

    @Test func nearestRatioHitsPublishedEntry() {
        // A room proportioned exactly Louden A (1 : 1.4 : 1.9): shortest 2.8 → 2.8×3.92×5.32.
        let r = RoomModes.nearestRatio(5.32, 3.92, 2.8)
        #expect(r.name == "Louden A")
        #expect(r.distance < 1e-6)
    }

    @Test func cubeIsDegenerateAndFailsBonello() {
        #expect(RoomModes.hasDegenerateRatio(5, 5, 5))                 // all sides equal
        #expect(RoomModes.bonelloPasses(lengthM: 5, widthM: 5, heightM: 5, speed: c, upToHz: 300) == false)
    }

    @Test func goodRoomPassesBonello() {
        #expect(RoomModes.bonelloPasses(lengthM: 5.32, widthM: 3.92, heightM: 2.8, speed: c, upToHz: 250))
        #expect(RoomModes.hasDegenerateRatio(5.32, 3.92, 2.8) == false)
    }

    @Test func spacingIsPositive() {
        let ms = RoomModes.modes(lengthM: 5, widthM: 4, heightM: 2.8, speed: c, maxHz: 200)
        #expect(RoomModes.smallestSpacing(ms) >= 0)
    }
}
