import Foundation
import GenerationKit

/// Which parts of the model the Neural Engine has already compiled on this device.
///
/// ### There is no API for this — this is bookkeeping, not detection
///
/// Core ML exposes no "is this graph compiled for the ANE" predicate. The compile runs out of
/// process in `ANECompilerService` and lands in a cache that is not readable from inside the
/// sandbox. Timing a load would answer the question only by paying the cost the question exists to
/// avoid, and the cache is per-model, so timing the 34 MB enlarger says nothing about the 648 MB
/// image model.
///
/// So the app records what it has compiled, itself. That is a weaker thing than detection and the
/// difference matters: the record can be wrong if the system purges its cache, in which case the
/// app skips a pass it should have run and the user pays a compile inside their first Create. The
/// named-component wake is the fallback for exactly that.
///
/// ### What the key is made of
///
/// Each part's id and byte count, the OS build, and the machine. **Not** modification dates: those
/// change on every reinstall even when the bytes are identical, so a key that included them would
/// throw away a valid record after every TestFlight update.
enum ModelWarmth {

    struct Key: Codable, Equatable {
        var parts: String
        var osBuild: String
        var hardware: String
    }

    struct Record: Codable, Equatable {
        var key: Key
        var compiled: [String]
    }

    /// Settable so tests get their own file rather than the test host's real one.
    static var markerURL: URL = {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil,
                                                 create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("model-warmth.json")
    }()

    static func key(for parts: [ModelPart]) -> Key {
        Key(parts: parts.map { "\($0.id):\($0.bytes)" }.sorted().joined(separator: "|"),
            osBuild: osBuild,
            hardware: hardware)
    }

    /// Part ids already compiled under this exact key. Empty when the model or the OS has moved.
    static func compiled(under key: Key) -> Set<String> {
        guard let data = try? Data(contentsOf: markerURL),
              let record = try? JSONDecoder().decode(Record.self, from: data),
              record.key == key else { return [] }
        return Set(record.compiled)
    }

    /// Records a completed part. Called **only after** its compile returned, so the record can never
    /// claim work that did not finish — a force-quit costs the part in flight and nothing else.
    static func note(_ partID: String, under key: Key) {
        var record = (try? Data(contentsOf: markerURL))
            .flatMap { try? JSONDecoder().decode(Record.self, from: $0) }
            ?? Record(key: key, compiled: [])
        if record.key != key { record = Record(key: key, compiled: []) }
        guard !record.compiled.contains(partID) else { return }
        record.compiled.append(partID)
        try? JSONEncoder().encode(record).write(to: markerURL, options: .atomic)
    }

    static func forget() { try? FileManager.default.removeItem(at: markerURL) }

    static var osBuild: String { sysctl("kern.osversion") }

    static var hardware: String {
        #if os(macOS)
        return sysctl("hw.model")
        #else
        return sysctl("hw.machine")
        #endif
    }

    private static func sysctl(_ name: String) -> String {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        guard size > 0 else { return "?" }
        var value = [CChar](repeating: 0, count: size)
        sysctlbyname(name, &value, &size, nil, 0)
        return String(cString: value)
    }
}
