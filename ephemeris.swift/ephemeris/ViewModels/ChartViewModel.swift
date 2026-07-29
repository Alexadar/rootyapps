import SwiftUI
import EphemerisKit

/// Drives the whole app: a chosen moment → positions, aspects, and the synodic cycle.
@MainActor
final class ChartViewModel: ObservableObject {
    // Any input change recomputes reactively (didSet doesn't fire during init, so the
    // init() recompute() still seeds the first result). During the demo scrub we only
    // recompute the chart (positions+aspects) so the animation stays smooth.
    @Published var date: Date { didSet { onInputChange() } }
    @Published var timeZone: TimeZone { didSet { persistTimeZone(); onInputChange() } }
    @Published var orbFactor: Double = 1.0 { didSet { onInputChange() } }
    @Published var cycleBody: CelestialBody = .mercury { didSet { onInputChange() } }

    /// Where the observer is. Houses and the angles are undefined without a place, so this is
    /// optional: nil simply means "no houses yet". Entered by hand — never from CoreLocation.
    @Published var location: GeoLocation? { didSet { persistLocation(); onInputChange() } }
    @Published var houseSystem: HouseSystem { didSet { persistHouseSystem(); onInputChange() } }

    private static let tzKey = "timeZoneIdentifier"
    private static let latKey = "observerLatitude"
    private static let lonKey = "observerLongitude"
    private static let placeKey = "observerPlaceName"
    private static let houseSystemKey = "houseSystem"

    private var demoTimer: Timer?
    private var demoActive = false
    private func onInputChange() { demoActive ? recomputeChartOnly() : recompute() }

    @Published private(set) var positions: [BodyPosition] = []
    @Published private(set) var aspects: [DetectedAspect] = []
    @Published private(set) var cyclePhase: SynodicPhase?
    @Published private(set) var upcomingEvents: [SynodicEvent] = []
    @Published private(set) var timelineEvents: [AstroEvent] = []

    /// Cusps for the chosen system, or nil when there's no location yet **or** the system is
    /// undefined there (Placidus/Koch beyond the polar circle). `houseFallback` says which.
    @Published private(set) var houses: HouseCusps?
    /// Set when the chosen system couldn't be computed and `houses` fell back to Whole Sign.
    @Published private(set) var houseFallback: HouseSystem?

    init() {
        date = Date()
        // EPHEMERIS_TZ overrides the persisted/device zone (used by preview reels); doesn't persist.
        let env = ProcessInfo.processInfo.environment
        let savedID = UserDefaults.standard.string(forKey: Self.tzKey) ?? TimeZone.current.identifier
        timeZone = TimeZone(identifier: env["EPHEMERIS_TZ"] ?? savedID) ?? .current

        let d = UserDefaults.standard
        houseSystem = HouseSystem(rawValue: d.string(forKey: Self.houseSystemKey) ?? "") ?? .placidus
        // EPHEMERIS_LAT / EPHEMERIS_LON mirror the EPHEMERIS_TZ convention so reels are
        // reproducible; they override the saved place without persisting.
        if let lat = Double(env["EPHEMERIS_LAT"] ?? ""), let lon = Double(env["EPHEMERIS_LON"] ?? "") {
            location = GeoLocation(latitude: lat, longitude: lon, name: env["EPHEMERIS_PLACE"])
        } else if d.object(forKey: Self.latKey) != nil, d.object(forKey: Self.lonKey) != nil {
            location = GeoLocation(latitude: d.double(forKey: Self.latKey),
                                   longitude: d.double(forKey: Self.lonKey),
                                   name: d.string(forKey: Self.placeKey))
        }
        recompute()   // didSet doesn't fire during init, so seed here
    }

    private func persistTimeZone() {
        UserDefaults.standard.set(timeZone.identifier, forKey: Self.tzKey)
    }

    private func persistHouseSystem() {
        UserDefaults.standard.set(houseSystem.rawValue, forKey: Self.houseSystemKey)
    }

    private func persistLocation() {
        let d = UserDefaults.standard
        guard let location else {
            [Self.latKey, Self.lonKey, Self.placeKey].forEach(d.removeObject(forKey:))
            return
        }
        d.set(location.latitude, forKey: Self.latKey)
        d.set(location.longitude, forKey: Self.lonKey)
        d.set(location.name, forKey: Self.placeKey)
    }

    /// The picked wall-clock numbers (as shown in the DatePicker, i.e. the device zone)
    /// interpreted in the chosen `timeZone` → the absolute instant fed to EphemerisKit.
    /// A `Calendar` in `timeZone` handles DST and fractional offsets correctly.
    var instant: Date {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = .current
        let c = local.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.date(from: c) ?? date
    }

    func recompute() {
        let t = instant
        recomputeChartOnly()
        cyclePhase = SynodicCycle.currentPhase(of: cycleBody, at: t)
        upcomingEvents = SynodicCycle.nextEvents(of: cycleBody, from: t, count: 6)
        let window = DateInterval(start: t.addingTimeInterval(-30 * 86_400),
                                  end: t.addingTimeInterval(120 * 86_400))
        timelineEvents = EventTimeline.allEvents(in: window)
    }

    /// Positions + aspects (+ houses) only — cheap enough to run every animation frame.
    /// Houses are closed-form, so they stay in step during the demo's date scrub.
    func recomputeChartOnly() {
        let t = instant
        positions = CelestialBody.allCases.map {
            BodyPosition(body: $0,
                         longitude: Ephemeris.longitude(of: $0, at: t),
                         speed: Ephemeris.dailyMotion(of: $0, at: t))
        }
        aspects = Aspects.detect(in: positions, orbFactor: orbFactor)
        recomputeHouses(at: t)
    }

    /// Whole Sign is the safety net: it's pure ecliptic geometry, so it works at every latitude.
    private func recomputeHouses(at t: Date) {
        guard let location else { houses = nil; houseFallback = nil; return }
        if let h = Houses.compute(at: t, location: location, system: houseSystem) {
            houses = h
            houseFallback = nil
        } else {
            houses = Houses.compute(at: t, location: location, system: .wholeSign)
            houseFallback = houseSystem
        }
    }

    // ── Demo (env EPHEMERIS_DEMO=1) — a choreographed "someone using the app": tap ► forward
    //    a day three times, then nudge the orb slider twice, on a calm ~1.2s beat. Each beat
    //    flashes the control it touches (`demoHighlight`) so the viewer sees what's tapped.
    //    Loops. Inert without the flag. ──
    enum DemoControl: Equatable { case forward, orb }
    @Published private(set) var demoHighlight: DemoControl?

    private let demoStart = Date()
    func startChartDemo() {
        guard ProcessInfo.processInfo.environment["EPHEMERIS_DEMO"] == "1" else { return }
        demoTimer?.invalidate()                    // (re)start cleanly from the first action
        demoActive = true
        demoHighlight = nil
        orbFactor = 1.0
        date = demoStart
        // Four slow, legible actions on a 1s beat: tap ► (+1 day) ×3, then sweep the orb slider
        // from its minimum up to ~75%. Each action lights the control it touches.
        //   iPhone/iPad: played ONCE (the reel tour restarts it inside the recorded window).
        //   mac (EPHEMERIS_DEMO_LOOP=1): loops, since the window-capture can't re-trigger it.
        let loop = ProcessInfo.processInfo.environment["EPHEMERIS_DEMO_LOOP"] == "1"
        var i = 0
        // Timer hands its block back on a non-isolated context, so every touch of this
        // @MainActor model is hopped explicitly rather than mutated from the Sendable closure.
        demoTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.demoActive else { return }
                let action = loop ? (i % 4) : i; i += 1
                if !loop && action >= 4 {                     // one pass complete → stop and hold
                    self.demoTimer?.invalidate(); self.demoTimer = nil
                    self.demoHighlight = nil
                    return
                }
                if action < 3 {
                    self.demoHighlight = .forward                          // press ►
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                        MainActor.assumeIsolated {
                            guard let self, self.demoActive else { return }
                            self.date = self.date.addingTimeInterval(86_400)  // …+1 day
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        MainActor.assumeIsolated { self?.demoHighlight = nil }
                    }
                } else {
                    self.demoHighlight = .orb                             // grab the orb slider
                    self.orbFactor = 0.5                                  // start at the minimum…
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
                        MainActor.assumeIsolated {
                            guard let self, self.demoActive else { return }
                            withAnimation(.easeInOut(duration: 0.75)) { self.orbFactor = 1.3 }  // …sweep to ~75%
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) { [weak self] in
                        MainActor.assumeIsolated { self?.demoHighlight = nil }
                    }
                }
            }
        }
    }

    func stopChartDemo() {
        demoTimer?.invalidate(); demoTimer = nil
        guard demoActive else { return }
        demoActive = false
        demoHighlight = nil
        orbFactor = 1.0
        date = demoStart          // settle back; triggers a full recompute
    }
}
