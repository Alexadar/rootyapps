import Foundation
import SwiftUI
import EphemerisKit

/// The chart library, and whichever chart is open.
///
/// Deliberately separate from `ChartViewModel`, which owns "the sky at a moment". A saved chart is a
/// *frozen* instant that must never be scrubbed, and the two states contradict each other: the
/// Moment card exists to move `date`, and moving it would quietly stop a chart being that person's.
/// Keeping them apart is why natal is a section rather than a mode.
@MainActor
final class NatalViewModel: ObservableObject {

    @Published private(set) var charts: [SavedChart] = []
    @Published var openChart: SavedChart?
    @Published var houseSystem: HouseSystem = .placidus
    /// Surfaced rather than swallowed — a library that fails to load must say so, not look empty.
    @Published var loadError: String?
    /// Where the charts actually are. Shown to the user, because "where is my data" is the question
    /// the competing apps answer badly.
    ///
    /// A plain `let`, not `@Published`: it is decided once when the store is chosen and never
    /// changes, and being non-isolated lets the nonisolated init below set it.
    let storage: StorageKind

    enum StorageKind {
        case iCloud
        /// iCloud Drive is off or the container is unavailable. Charts still save, on this device
        /// only — which the user must be told, not left to discover when a second device is empty.
        case local
    }

    private let store: ChartStore

    /// `nonisolated` so a `@StateObject` property initialiser can build it — those run outside the
    /// actor, and a MainActor-only init is an error there under Swift 6.
    nonisolated init(store: ChartStore, storage: StorageKind = .local) {
        self.store = store
        self.storage = storage
        // `charts` is MainActor-isolated and cannot be filled here. The library calls `reload()`
        // when it appears — which is also what a user expects after the app has been backgrounded
        // while another device wrote a chart.
    }

    /// The real one: iCloud when it is available, on-device otherwise.
    ///
    /// Falling back rather than failing is deliberate. A user with iCloud Drive switched off must
    /// still be able to save charts; refusing would make the feature look broken for a setting they
    /// chose. What must never happen is failing *silently* into local storage while implying sync —
    /// hence `storage`, which the library screen reports.
    nonisolated static func live() -> NatalViewModel {
        if let cloud = try? ICloudChartStore() {
            return NatalViewModel(store: cloud, storage: .iCloud)
        }
        if let local = try? FileChartStore() {
            return NatalViewModel(store: local, storage: .local)
        }
        return NatalViewModel(store: InMemoryChartStore(), storage: .local)
    }

    /// Previews and tests — the mock, seeded so the library is never empty while building UI.
    nonisolated static func mock() -> NatalViewModel {
        NatalViewModel(store: InMemoryChartStore(seed: NatalViewModel.sampleCharts))
    }

    func reload() {
        do {
            charts = try store.all()
            loadError = nil
        } catch {
            charts = []
            loadError = error.localizedDescription
        }
    }

    func save(_ chart: SavedChart) {
        do { try store.save(chart); reload() }
        catch { loadError = error.localizedDescription }
    }

    func delete(_ chart: SavedChart) {
        do { try store.delete(id: chart.id); reload() }
        catch { loadError = error.localizedDescription }
    }

    // MARK: - Derived, for the open chart

    var positions: [BodyPosition] { openChart?.positions ?? [] }
    var aspects: [DetectedAspect] { openChart?.aspects ?? [] }
    /// Nil when the birth time is unknown — the view must show that, not hide it.
    var houses: HouseCusps? { openChart?.houses(system: houseSystem) }
    var transits: [CrossAspect] { openChart?.transits() ?? [] }

    /// Where the transiting bodies are right now — the outer ring of the bi-wheel.
    var transitPositions: [BodyPosition] {
        let now = Date()
        return CelestialBody.allCases.map {
            BodyPosition(body: $0,
                         longitude: Ephemeris.longitude(of: $0, at: now),
                         speed: Ephemeris.dailyMotion(of: $0, at: now))
        }
    }

    // MARK: - Sample data

    /// Two charts with public birth data, so the library is never empty while building the UI.
    /// Delete once the file store is wired.
    /// `nonisolated` because it is used as a default argument to `init`, which is evaluated outside
    /// the actor — a MainActor-isolated static there is an error under Swift 6.
    nonisolated static let sampleCharts: [SavedChart] = {
        func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s) ?? Date() }
        return [
            SavedChart(name: "Sample — timed",
                       birthInstant: iso("1990-03-15T14:30:00Z"),
                       timeZoneID: "Europe/Berlin",
                       isTimeKnown: true,
                       latitude: 52.52, longitude: 13.405, placeName: "Berlin"),
            SavedChart(name: "Sample — time unknown",
                       birthInstant: iso("1975-07-04T12:00:00Z"),
                       timeZoneID: "America/Los_Angeles",
                       isTimeKnown: false,
                       latitude: 34.052, longitude: -118.244, placeName: "Los Angeles"),
        ]
    }()
}
