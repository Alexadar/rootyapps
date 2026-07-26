import Foundation
import Combine

/// Loads every source concurrently, keeps the last-good value for any panel whose fetch fails,
/// and is honest about which ones actually refreshed. This app needs the network for live data —
/// when a source is down we say so per panel and show the age of what we last had, never a
/// fabricated number.
///
/// Starts from the app-group cache (instant paint, shared with widgets/watch) and merges every
/// successful refresh back into it.
@MainActor
public final class SpaceWeatherStore: ObservableObject {
    @Published public private(set) var snapshot = SpaceWeatherSnapshot()
    @Published public private(set) var isLoading = false
    @Published public private(set) var lastRefresh: Date?
    @Published public private(set) var status = FeedStatus()

    /// No connectivity at all, or paused because the user turned cellular off. NOT "every fetch
    /// threw" — six dead feeds on a live connection used to still read as online.
    @Published public private(set) var blocked: FetchOutcome?

    public var isOffline: Bool { blocked == .skippedOffline }
    public var isPausedOnCellular: Bool { blocked == .skippedCellular }

    /// Runs after every successful refresh with the fresh snapshot — the app hangs alert
    /// evaluation and widget-timeline reloads here.
    public var afterRefresh: ((SpaceWeatherSnapshot) -> Void)?

    private var timer: Timer?
    private let shared = SharedStore()
    private var lastAttempt: Date?

    public init() {
        if let cached = shared.load() {
            snapshot = cached.snapshot
            lastRefresh = cached.at
        }
        status = shared.status
    }

    /// Refresh unless we already tried within `minInterval`. Screen changes call this; pull-to-
    /// refresh calls `refresh()` directly and always goes.
    public func refreshIfStale(minInterval: TimeInterval = 60) async {
        if let lastAttempt, Date().timeIntervalSince(lastAttempt) < minInterval { return }
        await refresh()
    }

    public func refresh() async {
        isLoading = true
        lastAttempt = Date()
        defer { isLoading = false }

        // Decide before spending seven requests, so the UI can explain the pause instead of
        // showing seven identical failures.
        let cellularAllowed = shared.cellularAllowed
        if let reason = NetworkMonitor.shared.blockedReason(cellularAllowed: cellularAllowed) {
            let now = Date()
            for source in FeedSource.allCases { status.record(source, reason, at: now) }
            blocked = reason
            shared.status = status
            return
        }
        blocked = nil

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

        let now = Date()
        var fresh = SpaceWeatherSnapshot()
        var freshStatus = FeedStatus()

        /// A 200 that decodes to nothing is not a success: an empty GFZ response used to replace a
        /// good Hp30 chart with an empty one and still report OK.
        func accept<T>(_ source: FeedSource, _ value: T?, isEmpty: (T) -> Bool = { _ in false },
                       apply: (T) -> Void) {
            guard let value else { freshStatus.record(source, .failed, at: now); return }
            guard !isEmpty(value) else { freshStatus.record(source, .empty, at: now); return }
            freshStatus.record(source, .ok, at: now)
            apply(value)
        }

        accept(.kp, kpP, isEmpty: { $0.series.isEmpty }) { fresh.kp = $0; snapshot.kp = $0 }
        accept(.flares, flareP, isEmpty: { $0.fluxSeries.isEmpty && $0.latestFlare == nil }) {
            fresh.flare = $0; snapshot.flare = $0
        }
        accept(.wind, windP, isEmpty: { $0.speed == nil && $0.bt == nil && $0.bz == nil }) {
            fresh.wind = $0; snapshot.wind = $0
        }
        accept(.scales, scalesP, isEmpty: { $0.observedAt == nil }) { fresh.scales = $0; snapshot.scales = $0 }
        accept(.solar, solarP, isEmpty: { $0.f107 == nil && $0.sunspotNumber == nil }) {
            fresh.solar = $0; snapshot.solar = $0
        }
        accept(.hpo, hpoP, isEmpty: { $0.readings.isEmpty }) { fresh.hpo = $0; snapshot.hpo = $0 }
        accept(.aurora, auroraP) { a in
            let panel = AuroraPanel(maxProbability: a.max, kp: snapshot.kp?.now ?? 0, observedAt: a.at)
            fresh.aurora = panel; snapshot.aurora = panel
        }

        status.merge(freshStatus)
        if !freshStatus.allFailed {
            lastRefresh = now
            shared.merge(fresh, status: freshStatus, at: now)
            afterRefresh?(snapshot)
        } else {
            shared.status = status
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
