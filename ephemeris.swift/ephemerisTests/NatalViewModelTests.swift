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

    /// `live()` must always end up with a usable library. iCloud off is a setting the user chose,
    /// not a failure, so it falls back rather than refusing to save.
    ///
    /// The store is now resolved **asynchronously**, because locating the iCloud container calls
    /// `FileManager.url(forUbiquityContainerIdentifier:)`, which Apple documents as unsafe to call
    /// on the main thread — doing it in `live()` hung the app on opening Charts with a cold
    /// container. So the invariant is unchanged but its timing is: after `resolveStore()`, saving
    /// always works.
    @MainActor
    @Test func liveProducesAStoreOnceResolved() async {
        let vm = NatalViewModel.live()
        await vm.resolveStore()
        vm.save(chart("Smoke"))
        #expect(vm.charts.contains { $0.name == "Smoke" })
        vm.charts.filter { $0.name == "Smoke" }.forEach { vm.delete($0) }
    }

    /// Before resolution the library must be *quiet*, not broken: no store yet is a loading state,
    /// so a save is a no-op and nothing is reported as an error. An empty library under a red
    /// "failed to load" banner reads as data loss.
    @MainActor
    @Test func beforeResolutionTheLibraryIsQuietRatherThanBroken() {
        let vm = NatalViewModel.live()
        #expect(vm.storage == .resolving, "storage must not claim a location it has not found")
        vm.reload()
        #expect(vm.charts.isEmpty)
        #expect(vm.loadError == nil, "a pending lookup is not a load failure")
        vm.save(chart("Ignored"))
        #expect(vm.charts.isEmpty, "a save before the store exists must not appear to succeed")
    }

    /// Resolution is idempotent — the library calls it on every appearance.
    @MainActor
    @Test func resolvingTwiceKeepsTheSameStore() async {
        let vm = NatalViewModel.live()
        await vm.resolveStore()
        let first = vm.storage
        await vm.resolveStore()
        #expect(vm.storage == first, "a second resolve must not swap the store out from under the UI")
        #expect(vm.storage != .resolving)
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
