import Testing
import Foundation
import EphemerisKit
@testable import ephemeris_swift

@Suite("ChartViewModel")
@MainActor
struct ViewModelTests {

    private func vmAt(_ date: Date, offset: Double = 0) -> ChartViewModel {
        let vm = ChartViewModel()
        vm.utcOffsetHours = offset
        vm.date = date
        vm.recompute()
        return vm
    }

    @Test func recomputePopulatesEverything() {
        let vm = vmAt(utc(2026, 6, 21, 12, 0))
        #expect(vm.positions.count == CelestialBody.allCases.count)
        #expect(vm.positions.allSatisfy { $0.longitude >= 0 && $0.longitude < 360 })
        #expect(!vm.aspects.isEmpty)
        #expect(vm.cyclePhase != nil)
        #expect(!vm.upcomingEvents.isEmpty)
    }

    @Test func changingDateChangesPositions() {
        let a = vmAt(utc(2026, 1, 1, 0, 0)).positions.first { $0.body == .mars }!.longitude
        let b = vmAt(utc(2026, 6, 1, 0, 0)).positions.first { $0.body == .mars }!.longitude
        #expect(abs(AstroMath.norm180(a - b)) > 1)
    }

    @Test func wideningOrbAddsAspects() {
        let vm = vmAt(utc(2026, 6, 21, 12, 0))
        vm.orbFactor = 0.5; vm.recompute(); let few = vm.aspects.count
        vm.orbFactor = 1.6; vm.recompute(); let many = vm.aspects.count
        #expect(many >= few)
    }

    @Test func switchingCycleBodyUpdatesPhase() {
        let vm = vmAt(utc(2026, 6, 21, 12, 0))
        vm.cycleBody = .venus; vm.recompute()
        #expect(vm.cyclePhase?.body == .venus)
    }

    @Test func utcOffsetShiftsInstant() {
        let vm = vmAt(utc(2026, 6, 21, 12, 0), offset: 0)
        let i0 = vm.instant
        vm.utcOffsetHours = 1
        let i1 = vm.instant
        #expect(abs(i1.timeIntervalSince(i0) - (-3600)) < 1) // +1h offset ⇒ instant 1h earlier
    }
}
