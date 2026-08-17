import Foundation
import Synchronization

/// Where environment events go.
///
/// Real observers — CallKit, `ProcessInfo`, `UIDevice`, `scenePhase` — implement this in the app.
/// So does the scripted mock below. That shared shape is what makes the entire interruption path
/// testable with no device: a test scripts "thermal goes critical at step 9" and the same code
/// path runs that the real notification would have driven.
public protocol EnvironmentEventSink: AnyObject, Sendable {
    func publish(_ event: RedesignQueue.Event)
}

/// Collects events instead of acting on them. For tests and previews.
public final class RecordingEventSink: EnvironmentEventSink, Sendable {
    private let storage = Mutex<[RedesignQueue.Event]>([])

    public init() {}

    public func publish(_ event: RedesignQueue.Event) {
        storage.withLock { $0.append(event) }
    }

    public var events: [RedesignQueue.Event] {
        storage.withLock { $0 }
    }

    public func reset() {
        storage.withLock { $0.removeAll() }
    }
}

/// Something that happens to the device partway through a render.
public enum ScriptedInterruption: Sendable, Equatable {
    case thermal(ThermalLevel)
    case call(active: Bool)
    case battery(BatterySnapshot)
    case scene(ScenePhaseState)
}

/// Wraps any generator and fires scripted interruptions at chosen steps.
///
/// Crucially it does **not** invent pauses of its own: it publishes through the same
/// `EnvironmentEventSink` the real observers use, so the reducer sees exactly the events it would
/// see on a warm phone with a call coming in. A mock that set `pause` directly would test the mock.
public final class InterruptibleRedesignGenerator: RedesignGenerator, @unchecked Sendable {

    public struct Cue: Sendable, Equatable {
        public let step: Int
        public let interruption: ScriptedInterruption
        public init(step: Int, interruption: ScriptedInterruption) {
            self.step = step
            self.interruption = interruption
        }
    }

    private let base: any RedesignGenerator
    private let cues: [Cue]
    private weak var sink: (any EnvironmentEventSink)?

    public var checkpointKind: String { base.checkpointKind }
    public var isReady: Bool { base.isReady }

    public init(base: any RedesignGenerator,
                cues: [Cue],
                sink: (any EnvironmentEventSink)?) {
        self.base = base
        self.cues = cues
        self.sink = sink
    }

    public func cancel() { base.cancel() }
    public func prewarm() async { await base.prewarm() }
    public func captureCheckpoint() async -> GenerationCheckpoint? { await base.captureCheckpoint() }
    public func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {
        try await base.prepare(progress: progress)
    }

    public func generate(_ request: RedesignRequest,
                         resuming checkpoint: GenerationCheckpoint?,
                         onStep: @escaping @Sendable (GenerationStep) -> Void) async throws -> RedesignOutput {
        let cues = self.cues
        let sink = self.sink
        return try await base.generate(request, resuming: checkpoint) { step in
            onStep(step)
            for cue in cues where cue.step == step.step {
                switch cue.interruption {
                case .thermal(let level): sink?.publish(.thermalChanged(level))
                case .call(let active): sink?.publish(.callChanged(active: active))
                case .battery(let snapshot): sink?.publish(.powerChanged(snapshot))
                case .scene(let phase): sink?.publish(.sceneChanged(phase))
                }
            }
        }
    }
}

/// Never returns a checkpoint and declares a kind nothing else writes.
///
/// Proves the degradation that matters most: a generator that cannot resume must produce a render
/// that restarts cleanly from zero, not a crash and not a stuck job. When the real Core ML
/// pipeline lands, "we could not checkpoint this model" has to be a supported configuration.
public final class RejectingCheckpointGenerator: RedesignGenerator, @unchecked Sendable {
    public let checkpointKind = "never"
    private let base: MockRedesignGenerator

    public init(speed: MockRedesignGenerator.Speed = .fast) {
        self.base = MockRedesignGenerator(speed: speed, checkpointKind: "never")
    }

    public func cancel() { base.cancel() }
    public func captureCheckpoint() async -> GenerationCheckpoint? { nil }

    public func generate(_ request: RedesignRequest,
                         resuming checkpoint: GenerationCheckpoint?,
                         onStep: @escaping @Sendable (GenerationStep) -> Void) async throws -> RedesignOutput {
        if let checkpoint {
            throw RedesignError.checkpointRejected(
                checkpoint.rejection(forKind: checkpointKind,
                                     digest: request.digest,
                                     deviceID: "mock-device") ?? .kindMismatch)
        }
        return try await base.generate(request, resuming: nil, onStep: onStep)
    }
}

/// Stands in for the monocular depth model that does not exist yet.
///
/// Writes a plausible synthetic disparity field — brighter toward the bottom of the frame, because
/// in a photograph of a room the floor in front of you genuinely is the nearest thing — and labels
/// its provenance honestly as `.synthetic`. It must never claim `.estimated`: that would put
/// "Depth estimated — geometry will hold" on screen over a gradient.
public final class MockDepthEstimator: DepthEstimator, @unchecked Sendable {
    private let provenance: DepthProvenance

    public init(provenance: DepthProvenance = .synthetic) {
        self.provenance = provenance
    }

    public func estimate(_ image: ImageHandle, writingTo destination: URL) async throws -> ControlSignal {
        let size = PixelSize(width: ControlImageRenderer.edge, height: ControlImageRenderer.edge)
        var values = [Float](repeating: 0, count: size.pixelCount)
        for y in 0..<size.height {
            // Disparity convention: large = near. The bottom of the frame is nearest.
            let nearness = Float(y) / Float(size.height - 1)
            for x in 0..<size.width {
                // A gentle horizontal bow, so a wipe across the result has something to track.
                let bow = 1 - abs(Float(x) / Float(size.width - 1) - 0.5) * 0.4
                values[y * size.width + x] = nearness * bow
            }
        }
        guard let rendered = ControlImageRenderer.render(values: values, size: size) else {
            throw RedesignError.depthUnavailable
        }
        try rendered.pixels.write(to: destination, options: .atomic)
        return ControlSignal(kind: .depth,
                             image: ImageHandle(url: destination, size: rendered.size),
                             provenance: provenance)
    }
}
