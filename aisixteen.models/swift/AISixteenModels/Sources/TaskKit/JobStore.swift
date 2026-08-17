import Foundation
import CoreML
import CoreGraphics
import ModelKit

/// Durable state for a long-running job, on disk.
///
/// The rules about *whether* work may be reused live in `JobKit` and are unit-tested without a
/// device. This is the part that actually touches the filesystem.
///
/// ### Application Support, not the temp directory
///
/// The system purges `temporaryDirectory` whenever it likes. A job stored there would vanish
/// between the interruption and the next launch — silently, and precisely in the case the feature
/// exists for. `Caches` is wrong for the same reason.
///
/// ### Everything is written the moment it is produced
///
/// A tile lands as its own file, atomically, as soon as it exists; a diffusion checkpoint replaces
/// the previous one. A crash costs one tile or four steps, never the job. The alternative —
/// accumulating in memory and writing once at the end — loses everything, which is the behaviour
/// being fixed.
public struct JobStore {

    public let manifest: JobManifest
    private let root: URL

    private var manifestURL: URL { root.appendingPathComponent("job.json") }
    private var checkpointURL: URL { root.appendingPathComponent("stage1.checkpoint") }
    private var tilesRoot: URL { root.appendingPathComponent("tiles", isDirectory: true) }

    public init(manifest: JobManifest) {
        self.manifest = manifest
        self.root = Self.jobsRoot.appendingPathComponent(manifest.id, isDirectory: true)
    }

    /// Settable so tests get their own directory instead of the test host's real one — a suite that
    /// wrote into Application Support would leave jobs behind that the app would then offer to
    /// resume.
    public static var jobsRoot: URL = {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil,
                                                 create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Jobs", isDirectory: true)
    }()

    // MARK: Manifest

    /// ISO 8601 **with fractional seconds**.
    ///
    /// Plain `.iso8601` truncates to whole seconds, and two jobs written in the same second then sort
    /// arbitrarily — so "the most recent interrupted job", which is the one the resume card offers,
    /// would be whichever the filesystem happened to enumerate first. Readable on disk, because this
    /// file is the only record of what a paused job was doing.
    private static let timestamps: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, target in
            var container = target.singleValueContainer()
            try container.encode(timestamps.string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { source in
            let text = try source.singleValueContainer().decode(String.self)
            guard let date = timestamps.date(from: text) else {
                throw DecodingError.dataCorruptedError(in: try source.singleValueContainer(),
                                                       debugDescription: "not a timestamp: \(text)")
            }
            return date
        }
        return decoder
    }

    public func begin() throws {
        try FileManager.default.createDirectory(at: tilesRoot, withIntermediateDirectories: true)
        try write(manifest)
    }

    public func storedManifest() -> JobManifest? {
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        return try? Self.decoder.decode(JobManifest.self, from: data)
    }

    /// Opens the job's directory, keeping what is already there **only if it is the same work**.
    ///
    /// Job ids are deterministic — enhancing the same wallpaper twice addresses the same directory —
    /// so that a second launch finds the first launch's tiles instead of starting a parallel job
    /// that will never be resumed. The price is that a changed prompt or step count now collides
    /// with the old job's files, which is exactly what this discards.
    public static func open(_ manifest: JobManifest) throws -> JobStore {
        let store = JobStore(manifest: manifest)
        if let existing = store.storedManifest(), !existing.describesSameWork(as: manifest) {
            store.discard()
        }
        try store.begin()
        return store
    }

    /// Records progress. Cheap enough to call per tile and per checkpoint — it is a few hundred
    /// bytes, and a job whose recorded stage lags behind its files would misreport on the resume
    /// card.
    public func record(stage: JobManifest.Stage) {
        var updated = manifest
        updated.stage = stage
        updated.updatedAt = Date()
        try? write(updated)
    }

    private func write(_ manifest: JobManifest) throws {
        try Self.encoder.encode(manifest).write(to: manifestURL, options: .atomic)
    }

    /// Deletes everything. A job the user cannot get rid of is worse than one they lose.
    public func discard() {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Tiles

    /// The two tiled stages, kept in separate directories.
    ///
    /// They must not share one: both number their tiles from zero over different grids, so a single
    /// directory would let stage 2's tile 3 be loaded as stage 3's — a patch of the wrong picture,
    /// at the wrong scale, with nothing reporting a problem.
    public enum TilePhase: String {
        case upscale
        case refine
    }

    public func tiles(_ phase: TilePhase) -> TileSet {
        TileSet(directory: tilesRoot.appendingPathComponent(phase.rawValue, isDirectory: true))
    }

    /// One stage's finished tiles on disk. Handed to `Upscaler` and `TileRefiner` so neither needs
    /// to know what a job is.
    public struct TileSet {
        public let directory: URL

        public func prepare() throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        public func completed() -> Set<Int> {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            return TileLedger.completed(in: names)
        }

        /// Atomic, and called the moment a tile exists. A crash costs that tile and nothing else.
        public func store(_ tile: CGImage, at index: Int) throws {
            guard let png = TileImage.png(from: tile) else {
                throw JobStoreError.tileNotWritten
            }
            try png.write(to: directory.appendingPathComponent(TileLedger.filename(index)),
                          options: .atomic)
        }

        public func load(_ index: Int) -> CGImage? {
            let url = directory.appendingPathComponent(TileLedger.filename(index))
            guard let data = try? Data(contentsOf: url) else { return nil }
            return TileImage.image(fromPNG: data)
        }

        /// Called once the stage's output has been composed and handed on. Leaving the tiles behind
        /// would let a later job with the same parameters resume into work it has already consumed.
        public func clear() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    // MARK: Stage 1 checkpoint

    /// The diffusion loop's entire resumable state — measured at ~800 KB for a 512² generation.
    public struct Checkpoint {
        public var step: Int
        public var lowerOrderStepped: Int
        public var latents: [MLShapedArray<Float32>]
        public var modelOutputs: [MLShapedArray<Float32>]

        public init(step: Int, lowerOrderStepped: Int,
                    latents: [MLShapedArray<Float32>], modelOutputs: [MLShapedArray<Float32>]) {
            self.step = step
            self.lowerOrderStepped = lowerOrderStepped
            self.latents = latents
            self.modelOutputs = modelOutputs
        }
    }

    public func writeCheckpoint(_ checkpoint: Checkpoint) {
        guard let data = Self.encode(checkpoint) else { return }
        try? data.write(to: checkpointURL, options: .atomic)
    }

    public func readCheckpoint() -> Checkpoint? {
        guard let data = try? Data(contentsOf: checkpointURL) else { return nil }
        return Self.decode(data)
    }

    /// A flat binary layout rather than `Codable`.
    ///
    /// The payload is a few hundred thousand `Float32`s. JSON would render each as a decimal string
    /// — several times the size, slower to write, and *lossy at the last bit*, which for restored
    /// diffusion state means the resumed picture differs subtly from the original. Raw little-endian
    /// floats round-trip exactly.
    public static func encode(_ checkpoint: Checkpoint) -> Data? {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        func append(_ array: MLShapedArray<Float32>) {
            append(UInt32(array.shape.count))
            for dimension in array.shape { append(UInt32(dimension)) }
            let scalars = array.scalars
            append(UInt32(scalars.count))
            scalars.withUnsafeBufferPointer { data.append(contentsOf: UnsafeRawBufferPointer($0)) }
        }

        append(UInt32(1))                                   // format version
        append(UInt32(checkpoint.step))
        append(UInt32(checkpoint.lowerOrderStepped))
        append(UInt32(checkpoint.latents.count))
        append(UInt32(checkpoint.modelOutputs.count))
        checkpoint.latents.forEach(append)
        checkpoint.modelOutputs.forEach(append)
        return data
    }

    public static func decode(_ data: Data) -> Checkpoint? {
        var offset = 0
        func read<T: FixedWidthInteger>() -> T? {
            let size = MemoryLayout<T>.size
            guard offset + size <= data.count else { return nil }
            defer { offset += size }
            return data.withUnsafeBytes { T(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: T.self)) }
        }
        func readArray() -> MLShapedArray<Float32>? {
            guard let rank: UInt32 = read() else { return nil }
            var shape: [Int] = []
            for _ in 0..<rank {
                guard let dimension: UInt32 = read() else { return nil }
                shape.append(Int(dimension))
            }
            guard let count: UInt32 = read() else { return nil }
            let bytes = Int(count) * MemoryLayout<Float32>.size
            guard offset + bytes <= data.count else { return nil }
            let scalars: [Float32] = data.withUnsafeBytes { raw in
                (0..<Int(count)).map {
                    raw.loadUnaligned(fromByteOffset: offset + $0 * 4, as: Float32.self)
                }
            }
            offset += bytes
            return MLShapedArray<Float32>(scalars: scalars, shape: shape)
        }

        guard let version: UInt32 = read(), version == 1,
              let step: UInt32 = read(),
              let lowerOrder: UInt32 = read(),
              let latentCount: UInt32 = read(),
              let outputCount: UInt32 = read() else { return nil }

        var latents: [MLShapedArray<Float32>] = []
        for _ in 0..<latentCount {
            guard let array = readArray() else { return nil }
            latents.append(array)
        }
        var outputs: [MLShapedArray<Float32>] = []
        for _ in 0..<outputCount {
            guard let array = readArray() else { return nil }
            outputs.append(array)
        }
        return Checkpoint(step: Int(step), lowerOrderStepped: Int(lowerOrder),
                          latents: latents, modelOutputs: outputs)
    }

    // MARK: Discovery

    /// Jobs left behind by an earlier launch, newest first.
    ///
    /// A job whose model no longer matches is **deleted here rather than offered**. Resuming it
    /// could not reproduce the same picture, and an offer that cannot be honoured is worse than no
    /// offer.
    public static func resumableJobs(matching installed: [ModelUse]) -> [JobManifest] {
        let directories = (try? FileManager.default.contentsOfDirectory(atPath: jobsRoot.path)) ?? []
        var found: [JobManifest] = []
        for directory in directories {
            let url = jobsRoot.appendingPathComponent(directory).appendingPathComponent("job.json")
            guard let data = try? Data(contentsOf: url),
                  let manifest = try? decoder.decode(JobManifest.self, from: data) else { continue }
            if manifest.canBeResumed(with: installed) {
                found.append(manifest)
            } else {
                JobStore(manifest: manifest).discard()
            }
        }

        // Newest first, and only a few kept. Every abandoned generation costs a checkpoint plus its
        // upscale tiles — tens of megabytes — and a job the user walked away from three sessions ago
        // is not one they are coming back to. Only the newest is ever offered anyway.
        // Tie-broken by id, because timestamps are stored to the millisecond and two jobs touched
        // inside the same one would otherwise come back in whatever order the directory was
        // enumerated in — making "the most recent interrupted job", the one the resume card offers,
        // a coin toss. Jobs are minutes apart in practice; the tie-break is so that the rule has an
        // answer at all rather than a usually-right one.
        let ordered = found.sorted {
            ($0.updatedAt, $0.id) > ($1.updatedAt, $1.id)
        }
        for stale in ordered.dropFirst(keptJobs) {
            JobStore(manifest: stale).discard()
        }
        return Array(ordered.prefix(keptJobs))
    }

    /// How many interrupted jobs survive a launch. More than one so that discarding the offer does
    /// not silently throw away an older one that is still worth finishing; small because they are
    /// not free.
    public static let keptJobs = 3

    /// The installed model's identity, from what the filesystem already knows. Content-hashing
    /// 1.1 GB on every launch would be absurd; a model update rewrites these files, and nothing
    /// else does.
    ///
    /// ### Sizes are summed recursively, and the size is the whole signal
    ///
    /// A compiled Core ML model is a **directory** — `ControlledUnet.mlmodelc` is a bundle, not a
    /// file. `URLResourceValues.fileSize` is nil for directories, so an earlier version of this
    /// summed to zero for every model and fingerprinted `name:0:mtime`: the size component looked
    /// live and contributed nothing. Measured, `ControlledUnet.mlmodelc` reports 224 bytes as a
    /// directory entry against 648 MB of actual contents.
    ///
    /// ### And mtime is deliberately not in it
    ///
    /// Modification dates change on every reinstall and every TestFlight update, even when the bytes
    /// are identical. Including them meant a paused job was thrown away after any app update — the
    /// fingerprint answering "was this app reinstalled" when it was asked "are these the same
    /// weights". Names and byte counts answer the question actually being asked.
    public static func fingerprint(ofModelAt resourcesURL: URL) -> String {
        let manager = FileManager.default
        let contents = (try? manager.contentsOfDirectory(at: resourcesURL,
                                                         includingPropertiesForKeys: nil)) ?? []
        let entries = contents.map { url in
            ModelFingerprint.Entry(name: url.lastPathComponent,
                                   size: bytes(of: url),
                                   modified: .distantPast)
        }
        return ModelFingerprint.of(entries)
    }

    /// Total bytes at `url`, whether it is a file or a directory of them.
    public static func bytes(of url: URL) -> Int {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }

        if !isDirectory.boolValue {
            return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        guard let walker = manager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
        else { return 0 }
        var total = 0
        for case let file as URL in walker {
            total += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }
}
