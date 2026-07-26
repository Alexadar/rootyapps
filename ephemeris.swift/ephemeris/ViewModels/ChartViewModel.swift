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

    private static let tzKey = "timeZoneIdentifier"

    private var demoTimer: Timer?
    private var demoActive = false
    private func onInputChange() { demoActive ? recomputeChartOnly() : recompute() }

    @Published private(set) var positions: [BodyPosition] = []
    @Published private(set) var aspects: [DetectedAspect] = []
    @Published private(set) var cyclePhase: SynodicPhase?
    @Published private(set) var upcomingEvents: [SynodicEvent] = []
    @Published private(set) var timelineEvents: [AstroEvent] = []

    init() {
        date = Date()
        // EPHEMERIS_TZ overrides the persisted/device zone (used by preview reels); doesn't persist.
        let envID = ProcessInfo.processInfo.environment["EPHEMERIS_TZ"]
        let savedID = UserDefaults.standard.string(forKey: Self.tzKey) ?? TimeZone.current.identifier
        timeZone = TimeZone(identifier: envID ?? savedID) ?? .current
        recompute()   // didSet doesn't fire during init, so seed here
    }

    private func persistTimeZone() {
        UserDefaults.standard.set(timeZone.identifier, forKey: Self.tzKey)
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

    /// Positions + aspects only — cheap enough to run every animation frame.
    func recomputeChartOnly() {
        let t = instant
        positions = CelestialBody.allCases.map {
            BodyPosition(body: $0,
                         longitude: Ephemeris.longitude(of: $0, at: t),
                         speed: Ephemeris.dailyMotion(of: $0, at: t))
        }
        aspects = Aspects.detect(in: positions, orbFactor: orbFactor)
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
        demoTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
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
                    guard let self, self.demoActive else { return }
                    self.date = self.date.addingTimeInterval(86_400)  // …+1 day
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.demoHighlight = nil
                }
            } else {
                self.demoHighlight = .orb                             // grab the orb slider
                self.orbFactor = 0.5                                  // start at the minimum…
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
                    guard let self, self.demoActive else { return }
                    withAnimation(.easeInOut(duration: 0.75)) { self.orbFactor = 1.3 }  // …sweep to ~75%
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) { [weak self] in
                    self?.demoHighlight = nil
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
