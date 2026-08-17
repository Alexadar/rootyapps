import Foundation
import FoundationModels
import Observation
import os
import TarotKit
import CardMotionKit

/// The state machine above the kernel. Screens are chrome states over ONE persistent 3D
/// scene: the menu shows the idle deck, the draw is the judged screen, the reading is a
/// panel over the landed cards. The kernel steps whenever a world exists — cards never
/// freeze, even behind the menu.
@MainActor
@Observable
final class AppModel {

    enum Screen { case menu, draw, reading }

    var screen: Screen = .menu

    // MARK: Settings (persisted)

    /// Reversed cards are PARKED (owner, 2026-08-17: "upside down cards are confusing —
    /// make all normal"). All machinery stays — TarotKit's first-class Orientation, the
    /// renderer's flip, the tests both ways — but every draw is upright and the Settings
    /// toggle is hidden. Flip this one flag to bring the feature back.
    /// (Research note, for the future: reversals-on is the RWS-tradition default and the
    /// off-toggle the category's most-requested setting — the owner chose clarity.)
    static let reversalsFeatureEnabled = false

    var allowsReversals: Bool = UserDefaults.standard.object(forKey: "allowsReversals") as? Bool ?? true {
        didSet { UserDefaults.standard.set(allowsReversals, forKey: "allowsReversals") }
    }

    /// What a draw actually uses: the user's stored preference, gated by the feature flag.
    static func effectiveAllowsReversals(_ userSetting: Bool) -> Bool {
        reversalsFeatureEnabled && userSetting
    }
    var hapticsEnabled: Bool = UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(hapticsEnabled, forKey: "hapticsEnabled")
            haptics.isEnabled = hapticsEnabled
        }
    }

    /// BGM is PARKED (owner, 2026-08-17: no bed made the cut — "drop bgm, only sfx").
    /// The whole music path — AudioController's bus, the fades, the toggle, AudioPlan —
    /// stays compiled; shipping a bed later = this flag + a bgm_arcana.m4a in Tarot/Audio.
    static let musicFeatureEnabled = false

    var musicEnabled: Bool = UserDefaults.standard.object(forKey: "musicEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(musicEnabled, forKey: "musicEnabled")
            applyMusicTarget()
        }
    }

    var soundsEnabled: Bool = AppModel.initialSounds() {
        didSet {
            UserDefaults.standard.set(soundsEnabled, forKey: "soundsEnabled")
            audio.soundsEnabled = soundsEnabled
        }
    }

    /// The Apple Intelligence toggle (owner, 2026-08-17): defaults ON wherever the model
    /// is present; turning it off keeps the draw whole and simply never asks the writer.
    var interpretationsEnabled: Bool = AppModel.initialInterpretations() {
        didSet { UserDefaults.standard.set(interpretationsEnabled, forKey: "interpretationsEnabled") }
    }

    /// A take must not inherit the owner's toggles: a saved `false` here would film a
    /// reading with no text at all, or a silent take. Property initializers, so nothing is
    /// ever written back to the owner's defaults.
    nonisolated static func initialInterpretations() -> Bool {
        #if DEBUG
        if let scenario = FilmScenario.fromLaunchArguments() { return scenario.interpretations }
        #endif
        return UserDefaults.standard.object(forKey: "interpretationsEnabled") as? Bool ?? true
    }

    nonisolated static func initialSounds() -> Bool {
        #if DEBUG
        if let scenario = FilmScenario.fromLaunchArguments() { return scenario.sounds }
        #endif
        return UserDefaults.standard.object(forKey: "soundsEnabled") as? Bool ?? true
    }

    /// Whether a draw should start the writer: the user's toggle AND the model existing.
    nonisolated static func shouldWrite(interpretationsEnabled: Bool, availability: WriterAvailability) -> Bool {
        interpretationsEnabled && availability == .available
    }

    /// Backgrounding fades the bed out; returning fades it back (tracked from scenePhase).
    private var sceneActive = true
    func setSceneActive(_ active: Bool) {
        sceneActive = active
        applyMusicTarget()
    }

    private func applyMusicTarget() {
        guard Self.musicFeatureEnabled else { return }
        audio.setMusicVolume(target: AudioPlan.targetMusicVolume(musicEnabled: musicEnabled,
                                                                 isActive: sceneActive))
    }

    /// Mirrors the system Reduce Motion setting into the kernel mode (set from the
    /// environment by the root view). A kernel mode, not a UI branch — see MotionConfig.
    var reduceMotion = false {
        didSet { refreshLayout() }
    }
    private(set) var config = MotionConfig.standard

    // MARK: Method & deck selection (persisted; pickers live on the menu)

    var selectedMethodID: String = AppModel.initialMethodID() {
        didSet {
            UserDefaults.standard.set(selectedMethodID, forKey: "selectedMethodID")
            refreshLayout()
            // The table re-lays itself live under the menu — the camera glides to the new
            // fit and the idle deck resets under the new geometry.
            if screen == .menu { resetIdleWorld() }
        }
    }

    var selectedDeckID: String = AppModel.initialDeckID() {
        didSet { UserDefaults.standard.set(selectedDeckID, forKey: "selectedDeckID") }
    }

    #if DEBUG
    /// The filming scenario, if this run is a take. Resolved once, here, because a property
    /// INITIALIZER does not fire `didSet` — see the note below for why that matters. Settable
    /// so the tests can drive a whole take headlessly without launch arguments.
    var scenario: FilmScenario? = FilmScenario.fromLaunchArguments()
    #endif

    /// The starting selections. A property INITIALIZER is deliberate: assigning these in
    /// `init` runs their `didSet` (the @Observable macro keeps observers alive there),
    /// which is how a Debug `-TAROT_METHOD` launch argument was silently overwriting the
    /// owner's saved choice — and why a later launch without the flag still ran Celtic.
    nonisolated static func initialMethodID() -> String {
        #if DEBUG
        if let scenario = FilmScenario.fromLaunchArguments() { return scenario.methodID }
        if let arg = LaunchOverride.argument("TAROT_METHOD") {
            return Spread.method(id: arg).id
        }
        #endif
        return UserDefaults.standard.string(forKey: "selectedMethodID") ?? "three-card"
    }

    nonisolated static func initialDeckID() -> String {
        #if DEBUG
        if let scenario = FilmScenario.fromLaunchArguments() { return scenario.deckID }
        if let arg = LaunchOverride.argument("TAROT_DECK") {
            return Deck.deck(id: arg).id
        }
        #endif
        return UserDefaults.standard.string(forKey: "selectedDeckID") ?? "classic-1909"
    }

    /// Registry lookups fall back to the defaults — a stale persisted id never crashes.
    var selectedMethod: Spread { Spread.method(id: selectedMethodID) }
    var selectedDeck: Deck { Deck.deck(id: selectedDeckID) }

    /// Method → kernel layout. Kept HERE (not in a Kit) because it is the one place the
    /// two kits' vocabularies meet; a test pins slotCount == positions.count for all.
    nonisolated static func layout(forMethodID id: String) -> MotionConfig {
        switch id {
        case "daily-card": .oneCard
        case "crossroads": .fiveCrossroads
        case "celtic-cross": .celticCross
        default: .threeCard
        }
    }

    nonisolated static func config(methodID: String, reduceMotion: Bool) -> MotionConfig {
        var c = layout(forMethodID: methodID)
        c.reduceMotion = reduceMotion
        return c
    }

    private func refreshLayout() {
        config = Self.config(methodID: selectedMethodID, reduceMotion: reduceMotion)
        renderer.setLayout(config: config, spread: selectedMethod)
    }

    /// The draw hint, as a pure policy over (landed, slotCount) — it was once hardcoded to
    /// the three-card counts and told a ten-card draw "the spread is complete" at three
    /// landings (found on device, 2026-08-17). Returns the English catalog key; counts
    /// beyond two-remaining share one count-neutral line because interpolated strings
    /// can't be catalog keys (ephemeris trap #4).
    nonisolated static func drawHintKey(landed: Int, slotCount: Int) -> String {
        if landed <= 0 { return "Drag a card from the deck to a position" }
        switch slotCount - landed {
        case ...0: return "The spread is complete"
        case 1: return "One more card"
        case 2: return "Two positions remain"
        default: return "Drag the next card to a position"
        }
    }

    /// Sampling seeds stay within Int32.max — MEASURED boundary (macOS 26.5, SDK 26.5):
    /// `GenerationOptions.SamplingMode.random(top:seed:)` takes a UInt64, but the model
    /// service fails any request whose seed exceeds 2³¹−1 (seed 2147483647 streams,
    /// 2147483648 dies with ModelManagerError 1032). Two billion readings is plenty.
    static let interpretationSeedRange: ClosedRange<UInt64> = 1 ... 0x7FFF_FFFF

    // MARK: Collaborators

    let renderer: any CardRenderer
    let haptics = HapticsController()
    let audio = AudioController()
    let writer: any ReadingWriter
    let composer = ReadingComposer()

    /// The deck's current dress. Swapping skins swaps the art interpreter (caches die with
    /// it) and re-dresses whatever scene is up — deck, faces and back alike.
    private(set) var artProvider = SkinnedArtProvider(skin: Skins.standard)

    /// The launch curtain, in two stages. `sceneReady` starts the dissolve; `curtainGone`
    /// says the app is fully on screen. Two flags rather than one because they mean different
    /// things to different callers: the view needs to know when to START fading, and the
    /// filming director needs to know when the fade has FINISHED, so a take never opens on a
    /// dissolve. Both are set by crossing a threshold exactly once — never recomputed per
    /// frame, or every observer would invalidate on every tick.
    private(set) var sceneReady = false
    private(set) var curtainGone = false
    private var launchElapsed: Double = 0
    /// Long enough for RealityKit to have drawn — and therefore uploaded — every material in
    /// the menu scene. There is no "textures are resident" callback to wait on, so this is a
    /// measured hold rather than a signal, and the dissolve on top of it hides the seam.
    static let curtainHold: Double = 0.65
    static let curtainFade: Double = 0.5

    func selectSkin(_ skin: any CardSkin) {
        guard skin.id != artProvider.skin.id else { return }
        artProvider = SkinnedArtProvider(skin: skin)
        rebuildCurrentScene()
    }

    // MARK: Session state

    private(set) var reading: Reading?
    private(set) var world: MotionWorld?
    private(set) var drawnLanes: [Int] = []       // lane per spread position
    var viewerLane: Int?
    /// The reader's optional question, typed on the menu. Rides into the interpretation;
    /// the shuffle never sees it.
    var question: String = ""
    /// AR is BUILT but PARKED (owner call, 2026-08-16: unstable on device — "later").
    /// Everything stays compiled and wired; flipping this single flag restores the AR
    /// buttons on menu and draw. Nothing else needs touching.
    static let arFeatureEnabled = false

    /// AR placement (iPhone/iPad): the card world sits on a real table at real-tarot scale.
    private(set) var arMode = false
    /// Mirrors the renderer's placement state so the chrome can offer Place / Re-place
    /// (the renderer isn't Observable; this is).
    private(set) var arPlaced = false

    // Pointer state, written by the gesture layer.
    var pointerX: Double = 0
    var pointerZ: Double = 0
    var pointerDown = false

    // Beat timers (seconds remaining). Hitstop freezes the kernel; a touch skips it.
    private var freezeRemaining: Double = 0
    private var heroFocusRemaining: Double = 0
    private var readingTransitionRemaining: Double = 0

    init(renderer: any CardRenderer, writer: any ReadingWriter) {
        self.renderer = renderer
        self.writer = writer
        haptics.isEnabled = hapticsEnabled
        audio.soundsEnabled = soundsEnabled
        // Stored-property defaults don't fire didSet — resolve the persisted method here.
        config = Self.config(methodID: selectedMethodID, reduceMotion: false)
    }

    // MARK: Lifecycle

    #if DEBUG
    /// Launch-argument self-probe (-TAROT_FM_PROBE): drive the real writer with a fixed,
    /// benign draw and report the outcome via os.Logger publicly — the only reliable
    /// channel out of a sandboxed app under `open -n`. Diagnostic for the 1032 hunt.
    var fmProbeStatus: String?

    private var fmProbeStarted = false

    private func fmProbeIfRequested() {
        guard !fmProbeStarted,
              LaunchOverride.present("-TAROT_FM_PROBE")
                || LaunchOverride.present("-TAROT_FM_PROBE_DELAYED") else { return }
        fmProbeStarted = true
        let reading = Reading(date: Date(), deckID: "classic-1909", spreadID: "three-card",
                              seed: 1, allowsReversals: false,
                              cards: [DrawnCard(card: .major(19), orientation: .upright, positionIndex: 0),
                                      DrawnCard(card: .minor(.cups, .six), orientation: .upright, positionIndex: 1),
                                      DrawnCard(card: .major(17), orientation: .upright, positionIndex: 2)],
                              interpretationSeed: 42)
        let delayed = LaunchOverride.present("-TAROT_FM_PROBE_DELAYED")
        fmProbeStatus = "probing (delayed: \(delayed))… availability: \(writer.availability)"
        let prompt = ReadingPrompt.prompt(reading: reading, deck: .classic1909, spread: .threeCard)
        // Two parallel probes: one through the writer on the main actor (the app's real
        // path), one raw and DETACHED — if only the detached one finishes, the main-actor
        // consumption is what starves the stream.
        Task { @MainActor in
            if delayed { try? await Task.sleep(nanoseconds: 20_000_000_000) }
            do {
                var updates = 0
                for try await _ in writer.write(reading: reading, deck: .classic1909, spread: .threeCard) {
                    updates += 1
                }
                fmProbeStatus = (fmProbeStatus ?? "") + " | main-actor: FINISHED \(updates)"
            } catch {
                fmProbeStatus = (fmProbeStatus ?? "") + " | main-actor FAILED: \(String(describing: error).prefix(120))"
            }
        }
        Task.detached {
            do {
                let session = LanguageModelSession(
                    instructions: ReadingPrompt.instructions(deck: .classic1909, spread: .threeCard))
                let stream = session.streamResponse(to: Prompt(prompt),
                                                    generating: WrittenReadingThree.self,
                                                    options: GenerationOptions(temperature: 0.8))
                var updates = 0
                for try await _ in stream { updates += 1 }
                let n = updates
                await MainActor.run { self.fmProbeStatus = (self.fmProbeStatus ?? "") + " | detached: FINISHED \(n)" }
            } catch {
                let text = String(describing: error).prefix(120)
                await MainActor.run { self.fmProbeStatus = (self.fmProbeStatus ?? "") + " | detached FAILED: \(text)" }
            }
        }
    }
    #endif

    /// RealityView's make-closure entry point. Runs on first appearance AND on every AR
    /// toggle (the view's identity changes, recreating it — runtime camera switching is
    /// broken platform-side). Rebuilds the stage for the current camera mode and restores
    /// whatever scene was up; the motion kernel's state survives untouched.
    func sceneRemade() {
        renderer.prepare()
        renderer.setLayout(config: config, spread: selectedMethod)
        haptics.prepare()
        audio.prepare()
        applyMusicTarget()
        #if DEBUG
        // Device motion would sweep the foil highlight differently in every take. Left
        // unstarted, `setPointerLight` stays writable and the take gets a scripted light.
        if scenario == nil { TiltSource.shared.start() }
        #else
        TiltSource.shared.start()
        #endif
        #if os(iOS)
        if arMode { renderer.setARMode(true) }
        #endif
        rebuildCurrentScene()
        #if DEBUG
        fmProbeIfRequested()
        #endif
    }

    /// The virtual-stage full reset (menu, non-AR paths).
    func prepareScene() {
        renderer.prepare()
        renderer.setLayout(config: config, spread: selectedMethod)
        resetIdleWorld()
    }

    /// Restore card entities to match the current screen: an in-progress draw/reading gets
    /// its faces back; anything else gets the idle deck.
    private func rebuildCurrentScene() {
        guard screen != .menu, let reading, !drawnLanes.isEmpty else {
            resetIdleWorld()
            return
        }
        // An in-progress reading restores under ITS OWN deck and method, whatever the
        // menu's current selection says.
        let deck = Deck.deck(id: reading.deckID)
        renderer.setLayout(config: Self.config(methodID: reading.spreadID, reduceMotion: reduceMotion),
                           spread: Spread.method(id: reading.spreadID))
        var faces: [Int: CardArt] = [:]
        var reversed: Set<Int> = []
        for (k, drawn) in reading.cards.enumerated() where drawnLanes.indices.contains(k) {
            faces[drawnLanes[k]] = artProvider.art(for: drawn.card, deck: deck)
            if drawn.orientation == .reversed { reversed.insert(drawnLanes[k]) }
        }
        renderer.build(deck: deck, faces: faces, back: artProvider.backArt(),
                       reversedLanes: reversed)
    }

    /// Rebuild just the deck/world (cards under `tableWorld`) — safe under an active AR
    /// anchor, unlike `renderer.prepare()`, which tears the whole stage down.
    private func resetIdleWorld() {
        var idle = MotionWorld(batch: 1, config: config, seed: 0xD1CE)
        idle.assignDeckOrder(Array(0..<idle.capacity), world: 0)
        world = idle
        renderer.build(deck: selectedDeck, faces: [:], back: artProvider.backArt(),
                       reversedLanes: [])
    }

    func startDraw() {
        let method = selectedMethod
        let deck = selectedDeck
        var systemRNG = SystemRandomNumberGenerator()
        var seed = UInt64.random(in: .min ... .max, using: &systemRNG)
        var drawDate = Date()
        #if DEBUG
        // A filmed take pins the seed, so the stack order, the lane order, the ambient
        // wobble phases and the juice streams are identical between takes.
        if let scenario { seed = scenario.seed; drawDate = scenario.date }
        #endif
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        var newReading = Shuffler.draw(deck: deck, spread: method, seed: seed,
                                       allowsReversals: Self.effectiveAllowsReversals(allowsReversals),
                                       date: drawDate,
                                       question: trimmedQuestion.isEmpty ? nil : trimmedQuestion)
        #if DEBUG
        // The ONLY correct place to force card identity: faces are keyed by lane and
        // `rebuildCurrentScene()` re-derives them from `reading`, so the substitution has to
        // live in the reading itself. The permutation is untouched — rewriting it would
        // desynchronise the stack geometry from the grab order.
        if let scenario { newReading = Self.forcing(scenario.cards, in: newReading) }
        #endif
        newReading.interpretationSeed = UInt64.random(in: Self.interpretationSeedRange,
                                                      using: &systemRNG)
        reading = newReading

        var newWorld = MotionWorld(batch: 1, config: config, seed: seed)
        // permutation[p] = deck index of the card at stack position p; the kernel wants the
        // inverse (lane → stack position).
        let order = Shuffler.permutation(count: newWorld.capacity, seed: seed)
        var depthByLane = [Int](repeating: 0, count: newWorld.capacity)
        for (position, deckIndex) in order.enumerated() { depthByLane[deckIndex] = position }
        newWorld.assignDeckOrder(depthByLane, world: 0)
        world = newWorld

        // The k-th grabbed card is deck.cards[order[k]] — its lane IS order[k].
        drawnLanes = (0..<method.positions.count).map { order[$0] }
        var faces: [Int: CardArt] = [:]
        var reversed: Set<Int> = []
        for (k, drawn) in newReading.cards.enumerated() {
            faces[drawnLanes[k]] = artProvider.art(for: drawn.card, deck: deck)
            if drawn.orientation == .reversed { reversed.insert(drawnLanes[k]) }
        }
        renderer.build(deck: deck, faces: faces, back: artProvider.backArt(),
                       reversedLanes: reversed)

        // The whole reading is decided here, so the writing starts HERE — the model runs
        // during the card play and the text is largely ready when the reading opens.
        // (This also replaces prewarm: the real request is its own warm-up.)
        composer.cancel()
        if Self.shouldWrite(interpretationsEnabled: interpretationsEnabled,
                            availability: writer.availability) {
            composer.start(reading: newReading, deck: deck, spread: method,
                           writer: writer)
        }
        audio.play(.shuffle)
        viewerLane = nil
        freezeRemaining = 0
        heroFocusRemaining = 0
        readingTransitionRemaining = 0
        screen = .draw
    }

    /// Replace a reading's card identities, preserving everything the rest of the app keys
    /// off: id (the panel's `onChange` trigger), date, deck, spread, seed and question. An
    /// arity mismatch is a deliberate no-op — a mis-authored scenario should film the real
    /// draw rather than a half-forced one.
    nonisolated static func forcing(_ forced: [Card]?, in reading: Reading) -> Reading {
        guard let forced, forced.count == reading.cards.count else { return reading }
        return Reading(id: reading.id, date: reading.date, deckID: reading.deckID,
                       spreadID: reading.spreadID, seed: reading.seed,
                       allowsReversals: reading.allowsReversals,
                       cards: forced.enumerated().map { index, card in
                           DrawnCard(card: card,
                                     orientation: reading.cards[index].orientation,
                                     positionIndex: index)
                       },
                       question: reading.question,
                       interpretationSeed: reading.interpretationSeed)
    }

    func toggleAR() {
        #if os(iOS)
        guard Self.arFeatureEnabled else { return }
        arMode.toggle()
        arPlaced = false
        // No renderer call here: flipping arMode changes the RealityView's identity, the
        // view is recreated, and sceneRemade() applies the mode on the fresh stage.
        haptics.play(.shimmerTick)
        #endif
    }

    /// "Place it here" — freeze the AR preview in world space; Re-place lifts it again.
    func fixateAR() {
        guard arMode, !arPlaced else { return }
        renderer.fixateARPlacement()
        arPlaced = true
        haptics.play(.land)
    }

    func replaceAR() {
        guard arMode, arPlaced else { return }
        renderer.unfixARPlacement()
        arPlaced = false
        haptics.play(.lift)
    }

    func backToMenu() {
        // Leaving the reading clears the question with it (owner, 2026-08-17): a stale
        // question sitting in the field would ride silently into the next draw, and the
        // reader would never know their new cards had been asked someone else's question.
        question = ""
        composer.cancel()
        viewerLane = nil
        renderer.setViewerFocus(lane: nil)
        renderer.setHeroFocus(false)
        // AR placement survives the trip to the menu — the placed table IS the scene now;
        // only the cards reset. The virtual stage does the full rebuild.
        if arMode { resetIdleWorld() } else { prepareScene() }
        screen = .menu
    }

    // MARK: Debug autopilot (a launch-argument test hook, Debug-only so it cannot ship —
    // uitests.md §4b discipline). Drives the same pointer a thumb would, so the whole
    // draw → flip → land → reading path can be verified headless in a simulator.

    #if DEBUG
    private var autopilotTime: Double? =
        LaunchOverride.present("-TAROT_AUTOPILOT") ? 0 : nil

    private func autopilotIntent(advancedBy dt: Double) -> (x: Double, z: Double, press: Bool)? {
        guard var t = autopilotTime else { return nil }
        t += dt
        autopilotTime = t
        if screen == .menu, t > 1.0 { startDraw() }
        guard screen == .draw else { return (0, 0, false) }
        let perCard = 2.0
        let card = min(Int((t - 1.0) / perCard), config.slotCount - 1)
        let local = ((t - 1.0) - Double(card) * perCard) / perCard
        guard card >= 0, local >= 0 else { return (0, 0, false) }
        let drag = min(max((local - 0.1) / 0.5, 0), 1)
        let eased = drag * drag * (3 - 2 * drag)
        let x = config.deckX + (config.slotX[card] - config.deckX) * eased
        let z = config.deckZ + (config.slotZ[card] - config.deckZ) * eased
        return (x, z, local >= 0.02 && local < 0.6)
    }
    #endif

    #if DEBUG
    /// The filming director: a twin of `autopilotIntent`, driven by `ScenarioTimeline` so all
    /// the arithmetic stays pure and testable. It replaces the autopilot rather than merging
    /// with it — the autopilot is load-bearing for the method UI tests and wants different
    /// beats than a camera does.
    private var scenarioTime: Double = 0
    private var scenarioStarted = false
    private var scenarioMarked: Set<String> = []
    private var scenarioEnded = false

    private func scenarioIntent(advancedBy dt: Double) -> (x: Double, z: Double, press: Bool)? {
        // Not one frame before the curtain has finished dissolving. T0 is what the capture
        // script trims against, so gating here is what makes a store preview open on the
        // loaded app instead of on the launch — the alternative was teaching the shell script
        // a magic offset, which would drift the moment these durations changed.
        guard let scenario, curtainGone else { return nil }
        let timeline = ScenarioTimeline(scenario: scenario, config: config)
        if scenarioTime == 0 {
            Self.filmLog.notice("SCENARIO_T0 \(scenario.id, privacy: .public) \(Date().timeIntervalSince1970)")
            if reduceMotion {
                // Not overridable — it mirrors a live system setting — but a take filmed with
                // it on has no roll, no juice and no flight arc. Say so, loudly.
                Self.filmLog.error("SCENARIO_WARN reduceMotion=1 — this take will not match")
            }
        }
        scenarioTime += dt
        let t = scenarioTime
        let beat = timeline.beat(at: t)

        if screen == .menu, !scenarioStarted {
            question = String(scenario.question.prefix(beat.typedCharacters))
        }
        for marker in timeline.markers where marker.at <= t && !scenarioMarked.contains(marker.key) {
            scenarioMarked.insert(marker.key)
            Self.filmLog.notice("SCENARIO_BEAT \(marker.key, privacy: .public) \(t) \(Date().timeIntervalSince1970)")
        }
        if beat.shouldStartDraw, !scenarioStarted {
            scenarioStarted = true
            question = scenario.question
            startDraw()
        }
        if beat.isOver, !scenarioEnded {
            scenarioEnded = true
            Self.filmLog.notice("SCENARIO_END \(Date().timeIntervalSince1970)")
        }
        return (beat.pointerX, beat.pointerZ, beat.press)
    }

    private static let filmLog = Logger(subsystem: "oleksandr.aisixteen.tarot", category: "scenario")
    #endif

    // MARK: The frame loop (driven by SceneEvents.Update)

    #if DEBUG
    /// Rolling frame cost, Debug only — the instrument for the GPU work. `dt` here is the
    /// real interval RealityKit hands us, so this reads the whole frame (render included),
    /// not just our step. Shown in the Debug chrome so a device can be measured directly:
    /// a fanless iPad that has started throttling shows it immediately.
    private(set) var frameStats: String?
    private var frameSamples: [Double] = []

    private func recordFrame(_ dt: Double) {
        // Never while filming. The HUD is a Debug overlay and a scenario only runs in Debug,
        // so every take was carrying "60 fps · 16.7 ms (p95 16.7)" across the top of the
        // screen — invisible in the capture log, obvious the moment anyone looks at a frame,
        // and an instant 2.3.4 problem in a store preview. Suppressed at the source rather
        // than in each of the two overlays that draw it, so a third one cannot reintroduce it.
        guard scenario == nil else { return }
        guard dt > 0, dt < 1 else { return }
        frameSamples.append(dt)
        guard frameSamples.count >= 60 else { return }
        let sorted = frameSamples.sorted()
        let median = sorted[sorted.count / 2]
        let worst = sorted[Int(Double(sorted.count) * 0.95)]
        frameStats = String(format: "%.0f fps · %.1f ms (p95 %.1f)", 1 / median,
                            median * 1000, worst * 1000)
        frameSamples.removeAll(keepingCapacity: true)
    }
    #endif

    func step(dt rawDT: Double) {
        #if DEBUG
        recordFrame(rawDT)
        #endif
        // A stall (backgrounding, a debugger pause) must not teleport the physics.
        let dt = min(max(rawDT, 0), 1.0 / 20.0)
        renderer.tick(dt: dt)

        if !curtainGone {
            launchElapsed += dt
            if !sceneReady, launchElapsed >= Self.curtainHold { sceneReady = true }
            if sceneReady, launchElapsed >= Self.curtainHold + Self.curtainFade { curtainGone = true }
        }

        #if DEBUG
        // The autopilot and the scenario director both call startDraw(), which replaces
        // `world` — so they must run BEFORE the local copy below, or the end-of-step
        // writeback clobbers the fresh world with a stale one. (Found live: the kernel
        // grabbed lanes 0/1/2 while the faces sat on the shuffled lanes.)
        if scenario != nil {
            if let take = scenarioIntent(advancedBy: dt) {
                pointerX = take.x
                pointerZ = take.z
                pointerDown = take.press
            }
        } else if let scripted = autopilotIntent(advancedBy: dt) {
            pointerX = scripted.x
            pointerZ = scripted.z
            pointerDown = scripted.press
        }
        #endif

        guard var w = world else { return }

        // A touch during any staged beat skips it (never tax the player).
        if pointerDown {
            freezeRemaining = 0
            if readingTransitionRemaining > 0 { readingTransitionRemaining = 1e-9 }
        }

        if heroFocusRemaining > 0 {
            heroFocusRemaining -= dt
            if heroFocusRemaining <= 0 { renderer.setHeroFocus(false) }
        }
        if readingTransitionRemaining > 0 {
            readingTransitionRemaining -= dt
            if readingTransitionRemaining <= 0 { presentReading() }
        }
        if freezeRemaining > 0 {
            // Hitstop: the kernel holds its breath (juice resumes exactly where it stopped —
            // the envelope runs on kernel time, which is frozen too).
            freezeRemaining -= dt
            return
        }

        let interactive = screen == .draw
        let intent = MotionIntent(
            pointerX: Tensor(shape: [1], data: [interactive ? pointerX : 0]),
            pointerZ: Tensor(shape: [1], data: [interactive ? pointerZ : 0]),
            press: Tensor(shape: [1], data: [interactive && pointerDown ? 1 : 0]),
            lightX: Tensor(shape: [1], data: [TiltSource.shared.lightX]),
            lightZ: Tensor(shape: [1], data: [TiltSource.shared.lightZ]))

        #if DEBUG
        logScenarioTextIfFinished()
        #endif
        let events = MotionStep.advance(&w, intent: intent, dt: dt, config: config)
        world = w
        renderer.apply(frame: MotionPose.poses(of: w, config: config))
        handle(events: events)
    }

    private func lane(in mask: Tensor) -> Int? { mask.setLanes(world: 0).first }

    private func handle(events: MotionEvents) {
        guard events.isEmpty == false else { return }

        if lane(in: events.grabbed) != nil {
            haptics.play(.lift)
            audio.play(.lift)
        }
        if let apexLane = lane(in: events.flipApex) {
            haptics.play(.flipApex)
            audio.play(.flip)
            // The hero interrupt (LoR level-up / Master Duel cut-in): a Major Arcana turning
            // over dims the table and pushes the camera in for a beat. Skippable by touch.
            if let reading, let k = drawnLanes.firstIndex(of: apexLane),
               reading.cards.indices.contains(k), reading.cards[k].card.arcana == .major,
               !config.reduceMotion {
                renderer.setHeroFocus(true)
                heroFocusRemaining = 0.9
            }
        }
        if let heroLane = lane(in: events.heroLanded) {
            haptics.play(.heroReveal)
            audio.play(.hero)
            renderer.playRevealBurst(lane: heroLane, hero: true)
            // The escalating-hitstop ladder tops out here: a 180 ms full freeze.
            freezeRemaining = config.reduceMotion ? 0 : 0.18
        } else if let landedLane = lane(in: events.landed) {
            haptics.play(.land)
            audio.play(.land)
            renderer.playRevealBurst(lane: landedLane, hero: false)
            freezeRemaining = config.reduceMotion ? 0 : 0.05
        }
        if events.drawComplete.data[0] > 0.5 {
            // Let the hero beat land, then bring in the reading.
            readingTransitionRemaining = 1.1
            #if DEBUG
            // -TAROT_FM_PROBE_POSTDRAW: fire the same fixed benign request the launch probe
            // uses, but AFTER a completed draw — the discriminating experiment for the
            // post-draw 1032 failures.
            if LaunchOverride.present("-TAROT_FM_PROBE_POSTDRAW") {
                let fixed = Reading(date: Date(), deckID: "classic-1909", spreadID: "three-card",
                                    seed: 1, allowsReversals: false,
                                    cards: [DrawnCard(card: .major(19), orientation: .upright, positionIndex: 0),
                                            DrawnCard(card: .minor(.cups, .six), orientation: .upright, positionIndex: 1),
                                            DrawnCard(card: .major(17), orientation: .upright, positionIndex: 2)],
                                    interpretationSeed: 42)
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    do {
                        var updates = 0
                        for try await _ in writer.write(reading: fixed, deck: .classic1909, spread: .threeCard) {
                            updates += 1
                        }
                        fmProbeStatus = "post-draw probe: FINISHED \(updates)"
                    } catch {
                        fmProbeStatus = "post-draw probe FAILED: \(String(describing: error).prefix(160))"
                    }
                }
            }
            #endif
        }
    }

    #if DEBUG
    /// A live scenario take writes its reading with the real model; this is how those words
    /// get out of the app and into the YAML. Emitted once, on the same log channel as the
    /// filming markers — read it with:
    ///   xcrun simctl spawn <UDID> log stream --predicate 'eventMessage CONTAINS "SCENARIO_TEXT"'
    private var loggedScenarioText = false

    func logScenarioTextIfFinished() {
        guard scenario != nil, !loggedScenarioText,
              case .finished(let draft) = composer.state else { return }
        loggedScenarioText = true
        for (index, passage) in draft.passages.enumerated() {
            Self.filmLog.notice("SCENARIO_TEXT passage \(index, privacy: .public): \(passage, privacy: .public)")
        }
        if let synthesis = draft.synthesis {
            Self.filmLog.notice("SCENARIO_TEXT synthesis: \(synthesis, privacy: .public)")
        }
    }
    #endif

    private func presentReading() {
        // Generation has been running since startDraw; this only reveals it.
        screen = .reading
    }

    // MARK: Immersive viewer

    func tapped(lane: Int) {
        guard screen == .reading, drawnLanes.contains(lane) else { return }
        if viewerLane == lane {
            viewerLane = nil
            renderer.setViewerFocus(lane: nil)
        } else {
            viewerLane = lane
            renderer.setViewerFocus(lane: lane)
            haptics.play(.shimmerTick)
            audio.play(.tick)
        }
    }
}
