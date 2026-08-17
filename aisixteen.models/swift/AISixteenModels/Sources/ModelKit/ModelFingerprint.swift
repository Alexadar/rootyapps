import Foundation

/// Identifies the installed model, so work made by one is never resumed into another.
///
/// The failure this prevents is silent and ugly: a wallpaper half-refined by the old model and half
/// by the new one, spliced at a tile boundary, with nothing anywhere reporting a problem. Since the
/// model arrives as an asset pack and can be updated underneath a paused job, the check is not
/// hypothetical.
///
/// Content hashing 1.1 GB on every launch would be absurd, so the fingerprint is built from what the
/// filesystem already knows — each compiled model's name, size and modification date. A model
/// update rewrites those files, so it changes; nothing else does.
///
/// Takes entries rather than reading a directory, so the rules are testable without a model on disk.
public enum ModelFingerprint {

    public struct Entry: Equatable, Sendable {
        public var name: String
        public var size: Int
        public var modified: Date

        public init(name: String, size: Int, modified: Date) {
            self.name = name
            self.size = size
            self.modified = modified
        }
    }

    /// Order-independent: a directory listing has no guaranteed order, and a fingerprint that
    /// changed with enumeration order would discard resumable jobs at random.
    public static func of(_ entries: [Entry]) -> String {
        let canonical = entries
            .map { "\($0.name):\($0.size):\(Int($0.modified.timeIntervalSince1970))" }
            .sorted()
            .joined(separator: "|")
        return String(format: "%016llx", fnv1a(canonical))
    }

    /// FNV-1a, not `hashValue`: Swift salts its hasher per process, so a fingerprint written on one
    /// launch would never match on the next — every job would look stale and resumption would
    /// silently never work.
    private static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
