import Foundation

public struct JobID: Hashable, Sendable, Codable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

/// Why a render stopped, in the user's terms.
///
/// The design handoff's copy for these four is the product: each card says what happened, what is
/// safe, and what resumes it. Interruptions are pauses, never errors — nothing here is a failure.
public enum GenerationPause: String, Sendable, Codable, CaseIterable, Hashable {
    case phoneCall
    case thermal
    case lowBattery
    case backgroundSuspended

    /// Which card is shown when several causes are true at once. Highest wins.
    ///
    /// Thermal sits at the bottom because its copy says "still progressing" — it must never mask a
    /// cause that actually stopped the work, or the user reads a reassuring sentence about a
    /// render that is not moving.
    public var displayPriority: Int {
        switch self {
        case .backgroundSuspended: return 3
        case .phoneCall: return 2
        case .lowBattery: return 1
        case .thermal: return 0
        }
    }

    public var title: String {
        switch self {
        case .phoneCall: return "Paused during your call."
        case .thermal: return "Running slower to keep the phone cool."
        case .lowBattery: return "Paused at 10% battery."
        case .backgroundSuspended: return "Waiting for you."
        }
    }

    public var detail: String {
        switch self {
        case .phoneCall:
            return "It resumes by itself when the call ends — nothing is lost."
        case .thermal:
            return "Time remaining updates as it goes. Setting the phone down helps."
        case .lowBattery:
            return "Progress is saved. Resumes on charge — or resume now."
        case .backgroundSuspended:
            return "This was set aside to save power. It picks up exactly where it left off when you open the app."
        }
    }

    /// Only low battery gives the user a choice. The others resolve by themselves, and a button
    /// that cannot change anything is worse than no button.
    public var offersResumeChoice: Bool { self == .lowBattery }
}

/// Thermal pressure, collapsed to the three levels that mean different things here.
/// `ProcessInfo`'s `.nominal` and `.fair` are the same story: nothing to say.
public enum ThermalLevel: Int, Sendable, Codable, Comparable, CaseIterable {
    case nominal = 0
    case elevated = 1
    case critical = 2

    public static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct BatterySnapshot: Sendable, Codable, Equatable, Hashable {
    /// 0…1. Meaningless when `isUnknown`.
    public let level: Double
    public let isCharging: Bool
    /// True on a device that does not report a battery, or before monitoring is enabled. A render
    /// must never be paused on a reading the system said it does not have.
    public let isUnknown: Bool
    public let lowPowerMode: Bool

    public init(level: Double, isCharging: Bool, isUnknown: Bool, lowPowerMode: Bool) {
        self.level = level
        self.isCharging = isCharging
        self.isUnknown = isUnknown
        self.lowPowerMode = lowPowerMode
    }

    /// A Mac on mains, and the state a fresh QueueState starts in.
    public static let unknown = BatterySnapshot(level: 1, isCharging: true, isUnknown: true, lowPowerMode: false)

    /// Pause below this, unplugged.
    public static let pauseThreshold = 0.10
    /// Resume above this. The gap is deliberate: without hysteresis a battery hovering at exactly
    /// 10% flaps the pause card on and off every few seconds.
    public static let resumeThreshold = 0.15
}

/// Where the app is, from the render's point of view.
///
/// This build claims NO background execution mode. `.flushing` is the short `beginBackgroundTask`
/// window taken for one purpose — writing the checkpoint cleanly — after which the job is
/// suspended and honestly says so.
public enum ScenePhaseState: String, Sendable, Codable, CaseIterable {
    case active
    /// Backgrounded, inside the short window granted to finish writing state.
    case flushing
    /// The window closed, or the app was backgrounded without one. Nothing is running.
    case suspended
}

public enum JobPhase: Equatable, Sendable, Codable, Hashable {
    case queued
    case running
    /// The displayed cause. Kept in sync with `Job.pauses` by the reducer — never set by hand.
    case paused(GenerationPause)
    case complete(outputID: String)
    case failed(reason: String)
    case cancelled

    /// Whether this job is still in the queue's way.
    public var isLive: Bool {
        switch self {
        case .queued, .running, .paused: return true
        case .complete, .failed, .cancelled: return false
        }
    }

    public var isTerminal: Bool { !isLive }
}

public struct Job: Equatable, Sendable, Codable, Identifiable {
    public let id: JobID
    public let request: RedesignRequest
    public var phase: JobPhase
    /// Every reason this job is not moving, not just the one on screen. A phone call during
    /// thermal throttling is both, and the handoff's single optional `pause` silently loses the
    /// second — so a thermal recovery would resume a render the user is still on a call for.
    public var pauses: Set<GenerationPause>
    /// Last COMPLETED step. 0 before the first.
    public var step: Int
    public var stage: GenerationStage
    /// Last step whose checkpoint is DURABLY WRITTEN. Nil when there is nothing to resume from.
    public var checkpointStep: Int?
    /// True after a saved checkpoint was refused. The run restarts from zero with the same seed;
    /// this is provenance, not an error.
    public var checkpointRejected: Bool
    /// True between the engine starting the generator and the generator stopping. The reducer
    /// needs it to tell "should start" from "is running" without asking anything outside itself.
    public var generatorRunning: Bool
    public var estimator: StepDurationEstimator
    public var enqueuedAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?
    /// "Resume anyway" was tapped on the low-battery card. Sticky, and scoped to this job only —
    /// overriding once must not silently opt every future render into draining the battery.
    public var lowBatteryOverridden: Bool

    public init(id: JobID,
                request: RedesignRequest,
                phase: JobPhase = .queued,
                pauses: Set<GenerationPause> = [],
                step: Int = 0,
                stage: GenerationStage = .reading,
                checkpointStep: Int? = nil,
                checkpointRejected: Bool = false,
                generatorRunning: Bool = false,
                estimator: StepDurationEstimator = StepDurationEstimator(),
                enqueuedAt: Date,
                startedAt: Date? = nil,
                finishedAt: Date? = nil,
                lowBatteryOverridden: Bool = false) {
        self.id = id
        self.request = request
        self.phase = phase
        self.pauses = pauses
        self.step = step
        self.stage = stage
        self.checkpointStep = checkpointStep
        self.checkpointRejected = checkpointRejected
        self.generatorRunning = generatorRunning
        self.estimator = estimator
        self.enqueuedAt = enqueuedAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.lowBatteryOverridden = lowBatteryOverridden
    }

    public var totalSteps: Int { request.plan.totalSteps }
    public var label: String { request.variationLabel }

    /// The one cause `PauseCard` shows.
    public var displayedPause: GenerationPause? {
        pauses.max { $0.displayPriority < $1.displayPriority }
    }

    /// Work is happening: either running outright, or throttled but still stepping.
    public var isProgressing: Bool {
        switch phase {
        case .running: return true
        case .paused(let cause): return cause == .thermal
        default: return false
        }
    }

    /// There is state worth saving that has not been saved.
    public var hasUnsavedProgress: Bool {
        step >= 1 && (checkpointStep ?? 0) < step
    }
}

public struct QueueState: Equatable, Sendable, Codable {
    /// Ordered. The head — the first live job — is the only one that ever runs.
    public var jobs: [Job]
    public var thermal: ThermalLevel
    public var callActive: Bool
    public var battery: BatterySnapshot
    public var scene: ScenePhaseState
    /// Latched by the hysteresis band, so a battery sitting at exactly the threshold does not
    /// flap the card. Global, because it describes the device, not a job.
    public var lowBatteryLatched: Bool
    /// True after jobs were rehydrated from disk at launch.
    ///
    /// Blocks auto-start. Burning minutes of Neural Engine time because somebody opened the app to
    /// look at their library is wrong; a cold-launched job waits for an explicit tap. Auto-resume
    /// belongs to the suspend path, where the engine was alive the whole time.
    public var restoredFromDisk: Bool
    /// Jobs whose checkpoint files should be deleted. Emptied as the engine confirms each.
    public var pendingCheckpointDiscards: [JobID]

    public init(jobs: [Job] = [],
                thermal: ThermalLevel = .nominal,
                callActive: Bool = false,
                battery: BatterySnapshot = .unknown,
                scene: ScenePhaseState = .active,
                lowBatteryLatched: Bool = false,
                restoredFromDisk: Bool = false,
                pendingCheckpointDiscards: [JobID] = []) {
        self.jobs = jobs
        self.thermal = thermal
        self.callActive = callActive
        self.battery = battery
        self.scene = scene
        self.lowBatteryLatched = lowBatteryLatched
        self.restoredFromDisk = restoredFromDisk
        self.pendingCheckpointDiscards = pendingCheckpointDiscards
    }

    /// The only job that runs.
    public var head: Job? { jobs.first { $0.phase.isLive } }

    public func job(_ id: JobID) -> Job? { jobs.first { $0.id == id } }

    /// Everything queued behind the head, in order. Feeds `GeneratingView`'s "Queued next:" line.
    public var queuedBehindHead: [Job] {
        guard let head else { return [] }
        return jobs.filter { $0.id != head.id && $0.phase == .queued }
    }

    public var queuedLabels: [String] { queuedBehindHead.map(\.label) }

    /// What the Live Activity prints as "N queued".
    public var queueDepth: Int { queuedBehindHead.count }

    public var isRunning: Bool { head?.phase == .running }

    /// Any live job at all — what the accent-drain rule keys off.
    public var hasLiveWork: Bool { head != nil }
}
