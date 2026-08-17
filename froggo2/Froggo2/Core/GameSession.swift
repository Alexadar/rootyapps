import Foundation
import Observation
import ReachabilityKit
import FroggoSim

enum GamePhase: Equatable {
    case menu
    /// Building and verifying a district. Brief, but it must exist: generation is real work and
    /// blocking the main actor on it is what made the first build launch to a white screen.
    case loading
    case aiming
    case flying
    case landed
    case gameOver
}

/// The game.
///
/// Everything the player does passes through here, and the flight is integrated from the *same*
/// `Ballistics` the solver used to certify the district. That is the whole architectural bet: the
/// arc drawn during aiming, the arc the frog flies, and the arc the oracle checked are one function,
/// so a route the solver promised is a route the player can actually fly. RealityKit runs no physics
/// at all — it draws where this says the frog is.
@Observable
@MainActor
final class GameSession {

    // MARK: - Configuration

    let config: WorldConfig

    // MARK: - World

    /// `nil` only while a district is being built. Every phase that reads it is unreachable until
    /// one exists.
    private(set) var districtOrNil: CityBlock?
    var district: CityBlock { districtOrNil! }
    var hasDistrict: Bool { districtOrNil != nil }

    private(set) var grade: DifficultyGrade?
    private(set) var districtIndex: Int = 0

    /// The rooftop the frog is standing on, when it is standing.
    private(set) var standingOn: RooftopID = RooftopID(0)

    // MARK: - Player state

    private(set) var phase: GamePhase = .menu
    private(set) var aimYaw: Double = 0
    private(set) var power: Double = 0
    private(set) var flyBanked: Bool = false

    private(set) var frogPosition: Vec3
    private(set) var frogVelocityYaw: Double = 0
    /// 0 at launch, 1 at landing — drives the frog's stretch and the camera's lead.
    private(set) var flightProgress: Double = 0

    // MARK: - Score

    private(set) var districtsCleared: Int = 0
    private(set) var roofsTouched: Int = 0
    private(set) var jumpsThisDistrict: Int = 0
    private(set) var best: Int = UserDefaults.standard.integer(forKey: "froggo2.best")

    var score: Int { districtsCleared * 10 + roofsTouched }
    /// Par for the current district — the solver's own minimum-jump count, shown to the player.
    /// Free depth that costs no art, and only possible because there is a solver.
    var par: Int { grade?.minJumps ?? 0 }

    // MARK: - Aim preview

    private(set) var previewArc: [Vec3] = []
    private(set) var previewLanding: Vec3?
    private(set) var previewIsReachable: Bool = false
    /// The rooftop the current aim would land on, if any.
    private(set) var previewTarget: RooftopID?

    // MARK: - Flight

    private var flightSpeed: Double = 0
    private var flightYaw: Double = 0
    private var flightTime: Double = 0
    private var flightDuration: Double = 0
    private var flightOrigin: Vec3 = .zero
    private var flightBoosted: Bool = false
    private var accumulator: Double = 0
    private var landedAt: RooftopID?


    // MARK: - Init

    init(config: WorldConfig = .shipping, seed: UInt64 = 0x5EED_F206_0810) {
        self.config = config
        self.baseSeed = seed
        self.frogPosition = .zero
    }

    private let baseSeed: UInt64
    /// The district after this one, built while the player is still crossing the current one, so
    /// arriving at the beacon never stalls.
    private var prefetched: (index: Int, result: DistrictFactory.Result)?

    /// Build a district off the main actor.
    ///
    /// `DistrictFactory` grades a whole candidate pool in one GPU pass and then runs the
    /// authoritative CPU verification on the single survivor it keeps — so this stays fast without
    /// weakening the guarantee that nothing unverified is ever played.
    private nonisolated static func build(index: Int, seed: UInt64,
                                          config: WorldConfig) async -> DistrictFactory.Result {
        await Task.detached(priority: .userInitiated) {
            DistrictFactory.make(index: index, seed: seed, config: config)
        }.value
    }

    // MARK: - Lifecycle

    func start() {
        Task { await beginRun() }
    }

    func restart() {
        Task { await beginRun() }
    }

    private func beginRun() async {
        phase = .loading
        districtsCleared = 0
        roofsTouched = 0
        jumpsThisDistrict = 0
        districtIndex = 0
        flyBanked = false
        prefetched = nil

        let first = await GameSession.build(index: 0, seed: baseSeed, config: config)
        adopt(first, index: 0)          // sets aimYaw to face the beacon
        phase = .aiming
        power = 0
        updatePreview()
        prefetchNext()
    }

    private func adopt(_ result: DistrictFactory.Result, index: Int) {
        districtOrNil = result.block
        grade = result.grade
        districtIndex = index
        standingOn = result.block.spawn
        frogPosition = result.block[result.block.spawn].standingPosition()
        jumpsThisDistrict = 0
        // Start facing the beacon. Yaw 0 points along -Z while districts run toward +Z, so leaving
        // it at zero pointed the camera out of the city at the top of every run — the player's first
        // sight of a district was the empty sky behind it.
        aimYaw = headingToGoal()
    }

    /// Ground heading from the frog to this district's goal rooftop.
    private func headingToGoal() -> Double {
        guard let block = districtOrNil else { return 0 }
        let from = block[standingOn].footprint.center
        let to = block[block.goal].footprint.center
        return (to - from).heading
    }

    /// Build the next district in the background while the player crosses this one.
    private func prefetchNext() {
        let next = districtIndex + 1
        guard prefetched?.index != next else { return }
        Task {
            let result = await GameSession.build(index: next, seed: baseSeed, config: config)
            if self.prefetched?.index != next { self.prefetched = (next, result) }
        }
    }

    func returnToMenu() { phase = .menu }

    // MARK: - Autopilot
    //
    // The scripted controller the plan called for. It exists for reel and screenshot capture — a
    // deterministic hands-free run — and it is only possible because the solver can be asked for the
    // actual shortest route rather than having to guess at one. The same hook is what a tvOS focus
    // controller or a headless balance sweep would drive.

    private(set) var autoPlay = false

    func enableAutoPlay() {
        autoPlay = true
        scheduleAutoJump()
    }

    private func scheduleAutoJump() {
        guard autoPlay else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard self.autoPlay else { return }
            switch self.phase {
            case .aiming: self.takeParStep()
            case .gameOver: self.restart()
            default: break
            }
            self.scheduleAutoJump()
        }
    }

    /// Aim at the next rooftop on the solver's own shortest route, and jump.
    private func takeParStep() {
        guard let block = districtOrNil else { return }
        let graph = ReachabilityGraph(block: block, config: config)
        guard let route = graph.route(from: standingOn, to: block.goal),
              let next = route.steps.first else { return }
        aimAt(next.to)
        launch()
    }

    // MARK: - Aiming

    func setAim(yaw: Double, power p: Double) {
        guard phase == .aiming else { return }
        aimYaw = yaw
        power = min(max(p, 0), config.powerCeiling)
        updatePreview()
    }

    /// Point at a rooftop and solve for the power that lands on it.
    ///
    /// This is the accessibility path and the tap-to-aim affordance — and it is also, for free, the
    /// control scheme tvOS will need, since a remote cannot express a continuous drag.
    func aimAt(_ id: RooftopID) {
        guard phase == .aiming, id != standingOn else { return }
        let from = district[standingOn]
        let to = district[id]
        let assessment = Reachability.assess(from: from, to: to, boosted: flyBanked, in: config)
        aimYaw = assessment.yaw
        if let required = assessment.requiredPower {
            // Aim a touch past the near edge so the landing is comfortably on the roof.
            power = min(config.powerCeiling, required + (assessment.powerWindow * 0.35))
        }
        updatePreview()
    }

    private func updatePreview() {
        guard phase == .aiming else {
            previewArc = []
            previewLanding = nil
            previewTarget = nil
            return
        }
        let origin = district[standingOn].standingPosition()
        let speed = Ballistics.speed(power: power, boosted: flyBanked, in: config)
        guard speed > 0 else {
            previewArc = []
            previewLanding = nil
            previewTarget = nil
            previewIsReachable = false
            return
        }

        let landingRoof = predictedLanding(origin: origin, speed: speed, yaw: aimYaw)
        let rise = (landingRoof.map { district[$0].height } ?? origin.y) - origin.y
        previewArc = Ballistics.arc(from: origin, speed: speed, yaw: aimYaw,
                                    rise: landingRoof == nil ? -config.deathDrop : rise,
                                    samples: 48, in: config)
        previewTarget = landingRoof
        previewIsReachable = landingRoof != nil
        previewLanding = previewArc.last
    }

    /// Which rooftop this shot lands on, if any.
    ///
    /// The arc is checked against each roof's own plane rather than a single ground plane, because
    /// rooftops sit at different heights and "where does it cross y = 0" would be the wrong question.
    private func predictedLanding(origin: Vec3, speed: Double, yaw: Double) -> RooftopID? {
        let direction = Vec2.direction(yaw: yaw)
        var bestRoof: RooftopID?
        var bestDistance = Double.infinity

        for roof in district.rooftops where roof.id != standingOn {
            let rise = roof.height - origin.y
            guard let d = Ballistics.range(speed: speed, rise: rise, in: config) else { continue }
            let landing = Vec2(origin.x + direction.x * d, origin.z + direction.z * d)
            guard roof.footprint.contains(landing) else { continue }
            if d < bestDistance {
                bestDistance = d
                bestRoof = roof.id
            }
        }
        return bestRoof
    }

    // MARK: - Launch

    func launch() {
        guard phase == .aiming, power > config.minPower else { return }
        let origin = district[standingOn].standingPosition()
        flightOrigin = origin
        flightSpeed = Ballistics.speed(power: power, boosted: flyBanked, in: config)
        flightYaw = aimYaw
        flightBoosted = flyBanked
        flightTime = 0
        flightProgress = 0
        jumpsThisDistrict += 1

        let target = predictedLanding(origin: origin, speed: flightSpeed, yaw: flightYaw)
        landedAt = target
        let rise = (target.map { district[$0].height } ?? (district.killPlaneY - origin.y + origin.y)) - origin.y
        flightDuration = Ballistics.flightTime(speed: flightSpeed, rise: rise, in: config)
            ?? Ballistics.flightTime(speed: flightSpeed, rise: district.killPlaneY - origin.y, in: config)
            ?? 2.0

        // The fly is spent on this jump whether or not it helps — the same as froggo 1, where
        // `flyEaten` was cleared immediately after the impulse was applied.
        flyBanked = false
        phase = .flying
        previewArc = []
        previewLanding = nil
    }

    // MARK: - Tick

    /// Advance the simulation by a rendered frame's worth of time.
    ///
    /// A fixed accumulator, not a variable step. Froggo 1 had two frame-rate-dependent bugs (a
    /// camera lerp of 0.15 *per frame* and a landing test of five consecutive *frames*), so it
    /// played measurably differently on a 120 Hz iPad than on a 60 Hz iPhone. Fixing the step means
    /// every device flies the same arc.
    func tick(_ delta: Double) {
        guard phase == .flying else { return }
        accumulator += min(delta, config.dt * Double(config.maxSubsteps))

        while accumulator >= config.dt {
            accumulator -= config.dt
            flightTime += config.dt
            let p = Ballistics.position(speed: flightSpeed, yaw: flightYaw, t: flightTime, in: config)
            frogPosition = Vec3(flightOrigin.x + p.x, flightOrigin.y + p.y, flightOrigin.z + p.z)
            flightProgress = flightDuration > 0 ? min(1, flightTime / flightDuration) : 1

            if frogPosition.y <= district.killPlaneY {
                die()
                return
            }
            if flightTime >= flightDuration {
                settle()
                return
            }
        }
    }

    private func settle() {
        guard let roof = landedAt else {
            die()
            return
        }
        standingOn = roof
        // Recentring is not tidiness — it is what makes the solver's model true. If the frog could
        // rest anywhere on a roof, reachability would depend on a continuous position and the graph
        // would not be finite. One node per rooftop is the assumption every proof here rests on.
        frogPosition = district[roof].standingPosition()
        roofsTouched += 1
        flightProgress = 0

        if district.flyRoofs.contains(roof) { flyBanked = true }

        if roof == district.goal {
            advanceDistrict()
        } else {
            phase = .aiming
            power = 0
            updatePreview()
        }
    }

    private func advanceDistrict() {
        districtsCleared += 1
        districtIndex += 1
        if score > best {
            best = score
            UserDefaults.standard.set(best, forKey: "froggo2.best")
        }

        // The next district was built while the player was still crossing this one, so arriving at
        // the beacon never stalls. If the prefetch has not landed yet, wait for it behind the
        // loading state rather than shipping an unverified district.
        if let ready = prefetched, ready.index == districtIndex {
            prefetched = nil
            adopt(ready.result, index: districtIndex)
            phase = .aiming
            power = 0
            updatePreview()
            prefetchNext()
        } else {
            phase = .loading
            let index = districtIndex
            Task {
                let result = await GameSession.build(index: index, seed: baseSeed, config: config)
                adopt(result, index: index)
                phase = .aiming
                power = 0
                updatePreview()
                prefetchNext()
            }
        }
    }

    private func die() {
        phase = .gameOver
        if score > best {
            best = score
            UserDefaults.standard.set(best, forKey: "froggo2.best")
        }
    }
}
