import Foundation
import SwiftUI
import BackgroundAssets
import GenerationKit
import FormatKit

/// The first-run gate's state, and the only thing that owns the download.
///
/// ## Why the pack is on-demand, not essential
///
/// `ba-package`'s own manifest template says it plainly: an **essential** asset pack "downloads
/// during your app's installation and blocks the user from opening the app until the installation
/// finishes." With that policy there is no consent screen, no in-app byte bar and no interrupted
/// state — the App Store does all four before the app ever launches, and every screen the design
/// bundle specifies in `4a` becomes unreachable code. The bundle is the authority, so the pack is
/// **on-demand** and the app asks for it here.
///
/// ## Progress is never simulated
///
/// Every byte on screen comes from `Foundation.Progress` handed over by `AssetPackManager`. The
/// generation progress in this build is mocked; the download progress is not, and must not be.
///
/// ## Pause, and what Background Assets actually offers
///
/// There is no app-callable pause or resume: the system owns the download lifecycle, pauses it when
/// the network or power situation requires, resumes on its own, and survives the app being killed.
/// So the card's chip does what the API can actually do — it lets the user *leave*, while the
/// download continues, and re-attaches to the live byte count when they come back. Resume is not a
/// feature written here; it is what the framework already guarantees, and the reason nothing in this
/// file ever restarts a transfer from zero.
@MainActor
@Observable
final class ModelGate {

    /// The asset pack's identifier, matching `AssetPacks/imagemodel/Manifest.json`.
    static let packID = "imagemodel"
    /// What the consent screen says the model weighs. A constant because the stand-in pack used
    /// during development is deliberately much smaller — the copy describes the shipping model.
    static let advertisedSize: Int64 = 2_600_000_000

    enum Phase: Equatable {
        /// A frame or two at launch while the pack's status is read. Renders as bare background —
        /// never as a flash of the consent screen at someone who installed the model months ago.
        case checking
        case consent
        case downloading(completed: Int64, total: Int64)
        /// The system paused it — waiting for Wi-Fi, or the network went away. Bytes are preserved.
        case interrupted(completed: Int64, total: Int64, reason: String)
        /// The model is installed and the Neural Engine is compiling it. Once per install, and
        /// again after an OS update. Counted in **parts**, because nothing inside one compile is
        /// measurable.
        ///
        /// Not `isFinished` — but `showsShell` lets the user walk straight past it.
        case tuning(part: Int, of: Int)
        case ready
        /// Not in the design bundle, and it has to exist: the allowance can be exceeded, the disk
        /// can be full, and the pack can be unreachable.
        case failed(reason: String)

        var isFinished: Bool { self == .ready }
    }

    /// What the gate reacts to, with `BackgroundAssets` factored out.
    ///
    /// `AssetPack` has no public initialiser and `Foundation.Progress` cannot be posted by hand, so
    /// a state machine written directly against `DownloadStatusUpdate` is a state machine that can
    /// only be tested by downloading two and a half gigabytes. Mapping the framework's updates onto
    /// this small enum first means every transition — including the ones that are awkward to
    /// provoke on a device, like a pause at 3 % or a failure after a pause — is covered by a unit
    /// test, and only the mapping itself needs a real download to verify.
    enum Event: Equatable {
        case began(total: Int64)
        case progressed(completed: Int64, total: Int64)
        case paused
        case finished
        /// The Neural Engine compile. Its own events rather than the byte-based download ones:
        /// parts are not bytes, and conflating them is how a counter starts lying.
        case tuningBegan(parts: Int)
        case tuningAdvanced(completed: Int, of: Int)
        case tuningFinished
        case failed(reason: String)
    }

    /// The pure transition. No framework, no clock, no I/O.
    static func reduce(_ phase: Phase, on event: Event, wifiOnly: Bool) -> Phase {
        switch event {
        case .began(let total):
            return .downloading(completed: 0, total: total)

        case .progressed(let completed, let total):
            // Clamped, because a progress object that reports more done than there is would
            // otherwise render a bar past the end of its track.
            let cap = max(total, 0)
            return .downloading(completed: min(max(completed, 0), cap), total: cap)

        case .paused:
            // Bytes are preserved. Whatever the transfer had reached is what the card keeps showing.
            let (done, total): (Int64, Int64)
            switch phase {
            case .downloading(let c, let t), .interrupted(let c, let t, _): (done, total) = (c, t)
            default: (done, total) = (0, advertisedSize)
            }
            return .interrupted(completed: done,
                                total: total,
                                reason: wifiOnly ? "Paused — waiting for Wi‑Fi."
                                                 : "Paused — waiting for a connection.")

        case .finished:
            return .ready

        case .tuningBegan(let parts):
            // `.ready` never regresses. Once the app is usable a late event may not put a setup
            // screen back in front of it.
            return phase == .ready ? .ready : .tuning(part: 0, of: max(parts, 0))

        case .tuningAdvanced(let completed, let total):
            guard phase != .ready else { return .ready }
            let cap = max(total, 0)
            return .tuning(part: min(max(completed, 0), cap), of: cap)

        case .tuningFinished:
            return .ready

        case .failed(let reason):
            return .failed(reason: reason)
        }
    }

    private(set) var phase: Phase = .checking

    /// The user chose "Look around meanwhile". The screen does not return this launch.
    private(set) var stoodAside = false

    /// The six rows. The phase carries the count; this carries which row is which.
    let checklist = TuningChecklist.State()

    private(set) var warmthKey: ModelWarmth.Key?

    /// Whether the app proper may be shown — ready, or the user walked past the compile.
    var showsShell: Bool { phase.isFinished || stoodAside }

    func lookAround() { stoodAside = true }

    /// Enters `.tuning` whenever there is anything left to compile, and returns what to skip.
    ///
    /// **Any remaining work earns the screen**, not only a first-ever launch. An earlier version
    /// showed it solely when nothing at all had been compiled, so the moment the first part landed
    /// every later launch fell through to a small chip — and the screen this design is built around
    /// was never once seen.
    func begin(tuning parts: [ModelPart]) -> Set<String> {
        let key = ModelWarmth.key(for: parts)
        let done = ModelWarmth.compiled(under: key)
        warmthKey = key
        checklist.begin(parts: parts, alreadyCompiled: done)
        guard done.count < parts.count else {
            markTuned()
            return done
        }
        apply(.tuningBegan(parts: parts.count))
        apply(.tuningAdvanced(completed: done.count, of: parts.count))
        return done
    }

    /// Nothing to compile — no parts, or a mock generator.
    func markTuned() {
        if !phase.isFinished { apply(.tuningFinished) }
    }

    /// Folds one tuning event into the phase, the checklist and the marker.
    func absorb(_ event: TuningEvent) {
        checklist.absorb(event)
        switch event {
        case .began:
            break
        case .finished(let part, _, let total, _):
            if let warmthKey { ModelWarmth.note(part.id, under: warmthKey) }
            if checklist.isFinished {
                apply(.tuningFinished)
            } else {
                apply(.tuningAdvanced(completed: checklist.completedCount, of: total))
            }
        case .stoodDown(let after, let total):
            apply(.tuningAdvanced(completed: after, of: total))
        case .failed:
            if checklist.isFinished { apply(.tuningFinished) }
        }
    }

    /// Default on, as specified. Off, or "use cellular this once", switches the download from the
    /// system-scheduled path to a foreground one that starts "regardless of battery or network
    /// status" — which is exactly what the control promises.
    var wifiOnly = true

    private var rate = TransferRateEstimator()
    private var updatesTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?

    // MARK: Display

    var completedBytes: Int64 {
        switch phase {
        case .downloading(let done, _), .interrupted(let done, _, _): return done
        default: return 0
        }
    }

    var totalBytes: Int64 {
        switch phase {
        case .downloading(_, let total), .interrupted(_, let total, _): return total
        default: return Self.advertisedSize
        }
    }

    var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(completedBytes) / Double(totalBytes)))
    }

    /// "1.1 of 2.6 GB"
    var byteText: String { ByteText.progress(completed: completedBytes, total: totalBytes) }

    /// "Wi‑Fi · 4.6 MB/s", or just the connection when there is no honest rate to quote yet.
    var rateText: String {
        let connection = wifiOnly ? "Wi‑Fi" : "Cellular"
        guard let measured = ByteText.rate(bytesPerSecond: rate.bytesPerSecond) else { return connection }
        return "\(connection) · \(measured)"
    }

    /// "About four minutes on this connection." Words, not a countdown that lurches.
    var remainingText: String {
        guard let phrase = ByteText.remainingPhrase(bytesRemaining: totalBytes - completedBytes,
                                                    bytesPerSecond: rate.bytesPerSecond)
        else { return "Feel free to leave — we'll be ready when you're back." }
        return "\(phrase) on this connection. Feel free to leave — we'll be ready when you're back."
    }

    // MARK: Lifecycle

    func start() async {
        // The gate's question is "is there a model?", not "did Background Assets deliver one?".
        // A build that carries the model in its bundle has already answered it, and asking the
        // asset-pack service anyway would put a download screen — or worse, a failure card — in
        // front of a user whose model is sitting right there. This is not a debug affordance: it
        // is the correct answer whenever the model is present by any route.
        #if WALLPAPERS_MOCK
        // The Mock configuration ships no model on purpose. There is nothing to download and
        // nothing to gate — the mock generator is always ready.
        phase = .ready
        return
        #else
        if CoreMLImageGenerator.bundledResourcesURL() != nil {
            phase = .ready
            return
        }

        #if DEBUG
        // A development affordance, not a skip. There is no user-facing way to bypass the gate —
        // the app genuinely cannot work without the model — but building the Create screen should
        // not require a live `ba-serve` on the desk. Compiled out of Release entirely.
        if let forced = LaunchOverride.value("WALLPAPERS_MODEL") {
            phase = forced == "installed" ? .ready
                  : forced == "failed" ? .failed(reason: "There wasn't enough room on this device.")
                  : .consent
            return
        }
        #endif

        if #available(iOS 26.4, macOS 26.4, *),
           AssetPackManager.shared.assetPackIsAvailableLocally(withID: Self.packID) {
            phase = .ready
            return
        }

        do {
            let status = try await AssetPackManager.shared.status(ofAssetPackWithID: Self.packID)
            if status.contains(.downloaded) || status.contains(.upToDate) {
                phase = .ready
                return
            }
            phase = .consent
            if status.contains(.downloading) {
                // A download was already running when the app was last killed. It kept going, so
                // re-attach to it rather than asking for consent to something already in flight.
                observeUpdates()
            }
        } catch {
            // Most commonly: no asset pack is being served. In development that means `ba-serve` is
            // not running; in production it means the pack could not be reached.
            phase = .failed(reason: Self.plainReason(for: error))
        }
        #endif
    }

    func beginDownload() {
        guard downloadTask == nil else { return }
        rate = TransferRateEstimator()
        observeUpdates()

        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let pack = try await AssetPackManager.shared.assetPack(withID: Self.packID)
                if await self.wifiOnly {
                    // System-scheduled: it honours the device's network and power policy, waits for
                    // Wi-Fi when it should, and reports `.paused` while it does.
                    try await AssetPackManager.shared.ensureLocalAvailability(of: pack)
                } else {
                    try await self.startInForeground(pack)
                }
                await MainActor.run { self.phase = .ready }
            } catch is CancellationError {
                // The user left the gate; the system keeps the transfer going.
            } catch {
                await MainActor.run { self.phase = .failed(reason: Self.plainReason(for: error)) }
            }
            await MainActor.run { self.downloadTask = nil }
        }
    }

    /// *Use cellular this once* — and the Wi-Fi-only toggle in its off position.
    ///
    /// `startForegroundDownload` is documented to start "immediately regardless of battery or
    /// network status". That is the honest implementation of a one-time override: scoped to this
    /// request, not a setting, and it does not change what the next launch does.
    func useCellularOnce() {
        wifiOnly = false
        downloadTask?.cancel()
        downloadTask = nil
        beginDownload()
    }

    /// *Keep waiting* — dismisses nothing, changes nothing. The system is already going to resume.
    func keepWaiting() {
        observeUpdates()
    }

    func retry() {
        phase = .consent
        downloadTask?.cancel()
        downloadTask = nil
        beginDownload()
    }

    func stopObserving() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    // MARK: -

    private func startInForeground(_ pack: AssetPack) async throws {
        let download = pack.download(for: .install)
        try BADownloadManager.shared.startForegroundDownload(download)
        // The status stream reports completion; there is nothing to await on the download itself.
        for await update in AssetPackManager.shared.statusUpdates(forAssetPackWithID: Self.packID) {
            if case .finished = update { return }
            if case .failed(_, let error) = update { throw error }
        }
    }

    private func observeUpdates() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            let stream = AssetPackManager.shared.statusUpdates(forAssetPackWithID: Self.packID)
            for await update in stream {
                guard let self else { return }
                await self.absorb(update)
            }
        }
    }

    /// Maps one framework update onto an `Event` and applies it. The only part of the gate's logic
    /// that a unit test cannot reach, and deliberately the smallest part.
    private func absorb(_ update: AssetPackManager.DownloadStatusUpdate) {
        let event: Event
        switch update {
        case .began(let pack):
            event = .began(total: Int64(pack.downloadSize))
        case .downloading(let pack, let progress):
            let total = progress.totalUnitCount > 0 ? progress.totalUnitCount : Int64(pack.downloadSize)
            let done = min(progress.completedUnitCount, total)
            rate.record(bytes: done, at: ProcessInfo.processInfo.systemUptime)
            event = .progressed(completed: done, total: total)
        case .paused:
            // A paused transfer is not moving, so the rate is dropped rather than frozen on screen.
            rate.stall()
            event = .paused
        case .finished:
            event = .finished
        case .failed(_, let error):
            event = .failed(reason: Self.plainReason(for: error))
        }

        apply(event)
    }

    /// Also the door the tests use.
    func apply(_ event: Event) {
        phase = Self.reduce(phase, on: event, wifiOnly: wifiOnly)
        if case .ready = phase { stopObserving() }
        if case .failed = phase { stopObserving() }
    }

    /// Plain words, no error codes. The three that actually happen get a sentence each; everything
    /// else gets an honest generic rather than a number the user cannot act on.
    private static func plainReason(for error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == BAErrorDomain else {
            return "The model couldn't be downloaded just now."
        }
        switch BAErrorCode(rawValue: nsError.code) {
        case .some(.downloadWouldExceedAllowance), .some(.sessionDownloadAllowanceExceeded):
            return "There isn't enough free space on this device for the model."
        case .some(.downloadBackgroundActivityProhibited):
            return "Low Power Mode is holding the download. Turning it off will let it finish."
        case .some(.callerConnectionInvalid), .some(.callerConnectionNotAccepted):
            return "The download service isn't reachable right now."
        default:
            return "The model couldn't be downloaded just now."
        }
    }
}
