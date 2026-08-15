import Testing
import Foundation
import EphemerisKit
@testable import Ephemeris

/// The library's state machine, against the in-memory store.
///
/// This is the layer between a `ChartStore` and the views, and it is where "saved but not shown" and
/// "deleted but still listed" bugs live. The store itself is covered by `ChartStoreTests`; these
/// check that the view model reflects it — including the case that matters most to a user, which is
/// being told plainly whether their charts are syncing or sitting on one device.
@Suite("Natal library")
struct NatalViewModelTests {

    private func chart(_ name: String, timeKnown: Bool = true) -> SavedChart {
        SavedChart(name: name,
                   birthInstant: ISO8601DateFormatter().date(from: "1990-03-15T14:30:00Z")!,
                   timeZoneID: "Europe/Berlin",
                   isTimeKnown: timeKnown,
                   latitude: 52.52, longitude: 13.405, placeName: "Berlin")
    }

    @MainActor
    @Test func savingAChartPutsItInTheLibrary() {
        let vm = NatalViewModel(store: InMemoryChartStore())
        #expect(vm.charts.isEmpty)

        vm.save(chart("Anna"))
        #expect(vm.charts.count == 1)
        #expect(vm.charts.first?.name == "Anna")
        #expect(vm.loadError == nil)
    }

    @MainActor
    @Test func deletingRemovesItFromTheLibraryButKeepsTheRecord() {
        let store = InMemoryChartStore()
        let vm = NatalViewModel(store: store)
        let c = chart("Bogdan")
        vm.save(c)
        vm.delete(c)

        #expect(vm.charts.isEmpty, "a deleted chart leaves the library")
        // The tombstone survives so an offline device cannot resurrect it — the store's contract.
        #expect((try? store.allIncludingDeleted().count) == 1)
    }

    @MainActor
    @Test func editingAChartReplacesItRatherThanDuplicating() {
        let vm = NatalViewModel(store: InMemoryChartStore())
        var c = chart("Original")
        vm.save(c)
        c.name = "Renamed"
        vm.save(c)

        #expect(vm.charts.count == 1, "same id must update, not append")
        #expect(vm.charts.first?.name == "Renamed")
    }

    /// The library reports where the data lives, and it must not claim sync it does not have — a
    /// second device showing an empty library is otherwise indistinguishable from data loss.
    @MainActor
    @Test func storageKindIsReportedHonestly() {
        #expect(NatalViewModel(store: InMemoryChartStore(), storage: .local).storage == .local)
        #expect(NatalViewModel(store: InMemoryChartStore(), storage: .iCloud).storage == .iCloud)
    }

    /// `live()` must always return a usable library. iCloud off is a setting the user chose, not a
    /// failure, so it falls back rather than refusing to save.
    @MainActor
    @Test func liveAlwaysProducesAStore() {
        let vm = NatalViewModel.live()
        vm.save(chart("Smoke"))
        #expect(vm.charts.contains { $0.name == "Smoke" })
        vm.charts.filter { $0.name == "Smoke" }.forEach { vm.delete($0) }
    }

    // MARK: - Derived

    @MainActor
    @Test func derivedValuesFollowTheOpenChart() {
        let vm = NatalViewModel(store: InMemoryChartStore())
        #expect(vm.positions.isEmpty, "nothing open, nothing derived")

        vm.openChart = chart("Anna")
        #expect(vm.positions.count == CelestialBody.allCases.count)
        #expect(!vm.aspects.isEmpty)
        #expect(vm.houses != nil)
        #expect(!vm.transits.isEmpty)
    }

    /// Houses must disappear with the birth time rather than being computed from an assumed noon.
    @MainActor
    @Test func anUntimedChartHasNoHouses() {
        let vm = NatalViewModel(store: InMemoryChartStore())
        vm.openChart = chart("Unknown time", timeKnown: false)
        #expect(vm.houses == nil)
        #expect(!vm.positions.isEmpty)
    }

    /// The bi-wheel's outer ring is the sky *now*, not the birth moment — a ring accidentally fed
    /// natal positions would render as a perfect conjunction with itself and look plausible.
    @MainActor
    @Test func transitPositionsAreTheCurrentSkyNotTheBirthMoment() {
        let vm = NatalViewModel(store: InMemoryChartStore())
        let c = chart("Anna")
        vm.openChart = c

        let outer = vm.transitPositions
        #expect(outer.count == CelestialBody.allCases.count)

        let natalSun = c.positions.first { $0.body == .sun }!.longitude
        let nowSun = outer.first { $0.body == .sun }!.longitude
        #expect(abs(nowSun - Ephemeris.longitude(of: .sun, at: Date())) < 0.001,
                "the outer ring is the live sky")
        #expect(AstroMath.separation(nowSun, natalSun) > 0.001,
                "and is not simply the natal positions again")
    }
}
