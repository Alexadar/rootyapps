import Foundation
import RedesignKit

/// Durable storage for in-flight denoising state, and for the queue itself.
///
/// **Deliberately NOT in iCloud**, and the reasons are worth keeping written down because the
/// container is right there and it looks convenient:
///
///   1. A checkpoint is device-local machine state. A latent produced on one device's Neural
///      Engine cannot be meaningfully continued on another — different silicon, possibly a
///      different model pack, and ANE numerics are not bit-reproducible across devices anyway.
///      Syncing it invites resuming garbage into a render the user will believe is finished.
///   2. The iCloud container is *visible in Files* — that is half the product's promise. A
///      multi-megabyte opaque `.bin` sitting beside the user's photos is junk, and it would be
///      the user's junk to look at.
///   3. `NSFileCoordinator` contention and an upload attempt on every write, in the hottest part
///      of the app.
///   4. A checkpoint is scratch, not an artefact. **Deleting every checkpoint must lose no user
///      data** — which is a test, and only stays true if they live somewhere separable.
struct CheckpointStore: Sendable {

    let root: URL

    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask)[0]
            self.root = support.appendingPathComponent("Renders", isDirectory: true)
        }
    }

    private var queueURL: URL { root.appendingPathComponent("queue.json") }

    private func folder(for id: JobID) -> URL {
        root.appendingPathComponent(id.rawValue, isDirectory: true)
    }

    private func blobURL(for id: JobID) -> URL {
        folder(for: id).appendingPathComponent("checkpoint.bin")
    }

    private func recordURL(for id: JobID) -> URL {
        folder(for: id).appendingPathComponent("checkpoint.json")
    }

    /// The metadata written beside the blob. Everything except `state`.
    private struct Record: Codable {
        var kind: String
        var requestDigest: String
        var step: Int
        var totalSteps: Int
        var deviceID: String
        var createdAt: Date
    }

    // ── writing ──────────────────────────────────────────────────────────────────────────────

    /// Blob first, record second, both atomic.
    ///
    /// The record is the commit: a `.bin` with no `.json` beside it is unreadable BY CONSTRUCTION
    /// rather than by convention, so a write interrupted by the process dying can never be
    /// mistaken for a complete one.
    func write(_ checkpoint: GenerationCheckpoint, for id: JobID) throws {
        try prepare()
        let directory = folder(for: id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try checkpoint.state.write(to: blobURL(for: id), options: .atomic)

        let record = Record(kind: checkpoint.kind,
                            requestDigest: checkpoint.requestDigest,
                            step: checkpoint.step,
                            totalSteps: checkpoint.totalSteps,
                            deviceID: checkpoint.deviceID,
                            createdAt: checkpoint.createdAt)
        try JSONEncoder().encode(record).write(to: recordURL(for: id), options: .atomic)
    }

    /// The version the background-expiration handler calls.
    ///
    /// Synchronous and non-throwing on purpose. The handler runs against a hard deadline, so it
    /// cannot `await captureCheckpoint()` — the engine keeps the newest bytes in memory and this
    /// writes exactly those. A handler that awaits is a handler that gets killed mid-write.
    @discardableResult
    func writeUrgently(_ checkpoint: GenerationCheckpoint, for id: JobID) -> Bool {
        do { try write(checkpoint, for: id); return true } catch { return false }
    }

    func read(for id: JobID) -> GenerationCheckpoint? {
        guard let recordData = try? Data(contentsOf: recordURL(for: id)),
              let record = try? JSONDecoder().decode(Record.self, from: recordData),
              let state = try? Data(contentsOf: blobURL(for: id)) else {
            return nil
        }
        return GenerationCheckpoint(kind: record.kind,
                                    requestDigest: record.requestDigest,
                                    step: record.step,
                                    totalSteps: record.totalSteps,
                                    deviceID: record.deviceID,
                                    state: state,
                                    createdAt: record.createdAt)
    }

    func discard(_ id: JobID) {
        try? FileManager.default.removeItem(at: folder(for: id))
    }

    // ── the queue ────────────────────────────────────────────────────────────────────────────

    func saveQueue(_ jobs: [Job]) {
        // Only live work is worth rehydrating. Finished, failed and cancelled jobs are history,
        // and history belongs in the library, not in a scratch file.
        let live = jobs.filter { $0.phase.isLive }
        guard !live.isEmpty else {
            try? FileManager.default.removeItem(at: queueURL)
            return
        }
        try? prepare()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(live) else { return }
        try? data.write(to: queueURL, options: .atomic)
    }

    func loadQueue() -> [Job] {
        guard let data = try? Data(contentsOf: queueURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Job].self, from: data)) ?? []
    }

    // ── housekeeping ─────────────────────────────────────────────────────────────────────────

    private func prepare() throws {
        var directory = root
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        // Scratch state, and megabytes of it. Backing it up would put a latent tensor in the
        // user's iCloud backup for no benefit at all.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
    }

    /// Run at launch, before anything is restored.
    ///
    /// Deletes half-written state (a blob with no record) and anything belonging to a job the
    /// queue no longer knows about — otherwise a crash during a render leaves megabytes behind
    /// forever, and nothing ever looks at it again.
    func sweep(keeping live: Set<JobID>) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil) else { return }

        for entry in entries where entry.hasDirectoryPath {
            let id = JobID(entry.lastPathComponent)
            let hasRecord = FileManager.default.fileExists(atPath: recordURL(for: id).path)
            if !live.contains(id) || !hasRecord {
                try? FileManager.default.removeItem(at: entry)
            }
        }
    }

    /// Every checkpoint in the app. Deleting all of these must lose no user data.
    func discardAll() {
        try? FileManager.default.removeItem(at: root)
    }
}
