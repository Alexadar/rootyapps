import Foundation
@testable import RedesignKit

/// Fixtures. Everything is explicit and nothing reads a real clock — `uptime` is supplied by the
/// test, so a three-minute render is exercised in microseconds.
enum Fixture {

    static let root = URL(fileURLWithPath: "/tmp/arch-tests", isDirectory: true)

    static func handle(_ name: String, width: Int = 3024, height: Int = 4032) -> ImageHandle {
        ImageHandle(url: root.appendingPathComponent(name),
                    size: PixelSize(width: width, height: height))
    }

    static func control(_ kind: ControlKind = .depth,
                        provenance: DepthProvenance = .lidar) -> ControlSignal {
        ControlSignal(kind: kind,
                      image: handle("depth.tiff", width: 512, height: 512),
                      provenance: provenance)
    }

    static func request(project: String = "living-room",
                        variation: Int = 1,
                        of count: Int = 1,
                        mode: SpaceMode = .interior,
                        prompt: String = "Bright Scandinavian living room, pale oak floor",
                        presetID: String? = "scandi",
                        seed: UInt32 = 4242,
                        plan: RedesignPlan = .standard,
                        controls: [ControlSignal]? = nil,
                        spaceName: String = "Living room",
                        styleName: String = "Scandinavian") -> RedesignRequest {
        RedesignRequest(id: "\(project)-\(variation)",
                        projectID: project,
                        variationIndex: variation,
                        variationCount: count,
                        source: handle("source.heic"),
                        controls: controls ?? [control()],
                        mode: mode,
                        prompt: prompt,
                        presetID: presetID,
                        seed: seed,
                        plan: plan,
                        spaceName: spaceName,
                        styleName: styleName)
    }

    static func job(_ request: RedesignRequest) -> Job {
        Job(id: JobID(request.id), request: request, enqueuedAt: Date(timeIntervalSince1970: 0))
    }

    /// N variations of one project, as the Direction screen's CTA would enqueue them.
    static func variations(_ count: Int,
                           project: String = "living-room",
                           mode: SpaceMode = .interior) -> [Job] {
        (1...count).map { index in
            job(request(project: project,
                        variation: index,
                        of: count,
                        mode: mode,
                        seed: UInt32(1000 + index)))
        }
    }

    static func battery(_ level: Double,
                        charging: Bool = false,
                        unknown: Bool = false,
                        lowPower: Bool = false) -> BatterySnapshot {
        BatterySnapshot(level: level, isCharging: charging, isUnknown: unknown, lowPowerMode: lowPower)
    }

    static func checkpoint(for request: RedesignRequest,
                           step: Int,
                           kind: String = "mock.v1",
                           deviceID: String = "mock-device") -> GenerationCheckpoint {
        GenerationCheckpoint(kind: kind,
                             requestDigest: request.digest,
                             step: step,
                             totalSteps: request.plan.totalSteps,
                             deviceID: deviceID,
                             state: Data([1, 2, 3, 4]),
                             createdAt: Date(timeIntervalSince1970: 100))
    }
}

/// Drives the reducer with a monotonic clock the test controls.
///
/// Holding the clock here rather than in the reducer is what makes "the estimate excludes pause
/// time" assertable without a twenty-minute test.
struct Driver {
    private(set) var state: QueueState
    private(set) var uptime: TimeInterval

    init(_ state: QueueState = QueueState(), uptime: TimeInterval = 1_000) {
        self.state = state
        self.uptime = uptime
    }

    mutating func send(_ event: RedesignQueue.Event, advancing seconds: TimeInterval = 0) {
        uptime += seconds
        state = RedesignQueue.reduce(state, on: event, at: uptime)
    }

    mutating func advance(_ seconds: TimeInterval) {
        uptime += seconds
    }

    var intent: Intent { state.intent }
    var head: Job? { state.head }
    var headPhase: JobPhase? { state.head?.phase }

    func job(_ id: JobID) -> Job? { state.job(id) }

    /// Enqueue and run through to `step`, the way the engine would.
    static func running(_ jobs: [Job], toStep step: Int = 0) -> Driver {
        var driver = Driver()
        driver.send(.enqueued(jobs))
        guard let head = driver.head else { return driver }
        driver.send(.started(head.id), advancing: 1)
        for index in stride(from: 1, through: step, by: 1) {
            let plan = head.request.plan
            driver.send(.stepped(head.id,
                                 step: index,
                                 stage: plan.stage(atStep: index),
                                 hasPreview: plan.emitsPreview(atStep: index)),
                        advancing: 4)
            if plan.offersCheckpoint(atStep: index) {
                driver.send(.checkpointWritten(head.id, step: index))
            }
        }
        return driver
    }
}
