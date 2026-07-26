import Foundation
import Combine

/// Loads every source concurrently, keeps the last-good value for any panel whose
/// fetch fails, and exposes refresh time + offline state honestly. This app needs
/// the network for live data — when a source is down we say so and show the age of
/// what we last had, never a fabricated number.
///
/// Starts from the app-group cache (instant paint, shared with widgets/watch) and
/// writes every successful refresh back to it.
@MainActor
public final class SpaceWeatherStore: ObservableObject {
    @Published public private(set) var snapshot = SpaceWeatherSnapshot()
    @Published public private(set) var isLoading = false
    @Published public private(set) var lastRefresh: Date?
    @Published public private(set) var isOffline = false

    /// Runs after every successful refresh with the fresh snapshot — the app hangs
    /// alert evaluation and widget-timeline reloads here.
    public var afterRefresh: ((SpaceWeatherSnapshot) -> Void)?

    private var timer: Timer?
    private let shared = SharedStore()

    public init() {
        if let cached = shared.load() {
            snapshot = cached.snapshot
            lastRefresh = cached.at
        }
    }

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }

        async let kp = try? NOAAService.kp()
        async let flares = try? NOAAService.flares()
        async let wind = try? NOAAService.solarWind()
        async let scales = try? NOAAService.scales()
        async let aurora = try? NOAAService.auroraProbability()
        async let solar = try? NOAAService.solarActivity()
        async let hpo = try? GFZService.hp30()

        let kpP = await kp
        let flareP = await flares
        let windP = await wind
        let scalesP = await scales
        let auroraP = await aurora
        let solarP = await solar
        let hpoP = await hpo

        // Keep last-good on partial failure; only overwrite what succeeded.
        if let kpP { snapshot.kp = kpP }
        if let flareP { snapshot.flare = flareP }
        if let windP { snapshot.wind = windP }
        if let scalesP { snapshot.scales = scalesP }
        if let solarP { snapshot.solar = solarP }
        if let hpoP { snapshot.hpo = hpoP }
        if let auroraP {
            // Kp drives the view-line latitude. With no Kp this falls back to 0, which reads as
            // a confident "visible down to 66°" — callers must gate that sentence on `kp != nil`.
            let kpNow = snapshot.kp?.now ?? 0
            snapshot.aurora = AuroraPanel(maxProbability: auroraP.max, kp: kpNow, observedAt: auroraP.at)
        }

        let allFailed = kpP == nil && flareP == nil && windP == nil && scalesP == nil
            && auroraP == nil && solarP == nil && hpoP == nil
        isOffline = allFailed
        if !allFailed {
            let now = Date()
            lastRefresh = now
            shared.save(snapshot, at: now)
            afterRefresh?(snapshot)
        }
    }

    public func startAutoRefresh(interval: TimeInterval = 300) {
        stopAutoRefresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    public func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
    }
}
