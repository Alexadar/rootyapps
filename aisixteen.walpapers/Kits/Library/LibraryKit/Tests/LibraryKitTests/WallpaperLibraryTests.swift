import Testing
import Foundation
import GenerationKit
@testable import LibraryKit

private func temporaryRoot() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("LibraryKitTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Spelled as an instant rather than an epoch number, so the expected filename below cannot drift
/// away from the date it is supposed to represent.
private let fixedDate = ISO8601DateFormatter().date(from: "2026-08-10T14:02:05Z")!

/// ORACLES:
///  • INVARIANT — a saved wallpaper round-trips: everything the design needs to show (prompt,
///    seed, size, date) comes back exactly as written. "Regenerate from this prompt" depends on it.
///  • INVARIANT — the same code, pointed at two different roots, behaves identically. This is the
///    iCloud-available / iCloud-unavailable axis of the state space, tested rather than assumed.
///  • BEHAVIOUR — a folder the user can see in Files will contain things we did not put there;
///    listing must ignore them rather than fail.
/// MODEL CAVEAT: `DirectFileAccess` is used throughout. Coordination behaviour under a live iCloud
/// daemon cannot be tested here — that is verified on device.
@Suite("WallpaperLibrary — save, list, delete, over any root")
struct WallpaperLibraryTests {

    private func makeLibrary(_ root: URL = temporaryRoot()) -> WallpaperLibrary {
        WallpaperLibrary(root: root, access: DirectFileAccess(), appVersion: "1.0.0")
    }

    @Test("a saved wallpaper comes back with every field intact")
    func roundTrip() throws {
        let library = makeLibrary()
        let saved = try library.save(imageData: Data([0xDE, 0xAD, 0xBE, 0xEF]),
                                     prompt: "molten glass poppies at dusk",
                                     seed: 0x3F9C1A,
                                     aspect: .phone,
                                     createdAt: fixedDate)
        let listed = try library.records()
        #expect(listed.count == 1)
        let record = try #require(listed.first)
        #expect(record.id == saved.id)
        #expect(record.prompt == "molten glass poppies at dusk")
        #expect(record.seed == 0x3F9C1A)
        #expect(record.aspect == AspectRatio.phone)
        #expect(record.createdAt.timeIntervalSince1970 == fixedDate.timeIntervalSince1970)
        #expect(record.metadata.version == WallpaperMetadata.currentVersion)
        #expect(try library.imageData(for: record) == Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }

    @Test("the filename is the date then a seed tag, with no colons")
    func filenameShape() {
        let stem = WallpaperFilename.stem(createdAt: fixedDate, seed: 0x3F9C1A)
        #expect(stem == "2026-08-10T14-02-05Z-3f9c1a", "got \(stem)")
        #expect(!stem.contains(":"))
        #expect(WallpaperFilename.imageName(stem).hasSuffix(".png"))
        #expect(WallpaperFilename.sidecarName(stem).hasSuffix(".json"))
    }

    @Test("two wallpapers finished in the same second do not overwrite each other")
    func sameSecondCollision() throws {
        let library = makeLibrary()
        try library.save(imageData: Data([1]), prompt: "one", seed: 111, aspect: .phone, createdAt: fixedDate)
        try library.save(imageData: Data([2]), prompt: "two", seed: 222, aspect: .phone, createdAt: fixedDate)
        let records = try library.records()
        #expect(records.count == 2)
        #expect(Set(records.map(\.prompt)) == ["one", "two"])
    }

    @Test("the same instant and seed overwrite, so a retried save does not duplicate")
    func retryOverwrites() throws {
        let library = makeLibrary()
        try library.save(imageData: Data([1]), prompt: "first attempt", seed: 7, aspect: .phone, createdAt: fixedDate)
        try library.save(imageData: Data([2]), prompt: "same again", seed: 7, aspect: .phone, createdAt: fixedDate)
        let records = try library.records()
        #expect(records.count == 1)
        #expect(records.first?.prompt == "same again")
    }

    @Test("the grid order is newest first and stable across refreshes")
    func newestFirst() throws {
        let library = makeLibrary()
        for offset in 0..<5 {
            try library.save(imageData: Data([UInt8(offset)]),
                             prompt: "number \(offset)",
                             seed: UInt32(offset),
                             aspect: .phone,
                             createdAt: fixedDate.addingTimeInterval(TimeInterval(offset * 60)))
        }
        let first = try library.records()
        #expect(first.map(\.prompt) == ["number 4", "number 3", "number 2", "number 1", "number 0"])
        #expect(try library.records().map(\.id) == first.map(\.id), "order must not reshuffle")
    }

    @Test("wallpapers from the same second still have a deterministic order")
    func stableOrderWithinASecond() throws {
        let library = makeLibrary()
        for seed in [UInt32(5), 1, 3] {
            try library.save(imageData: Data([UInt8(seed)]), prompt: "s\(seed)",
                             seed: seed, aspect: .phone, createdAt: fixedDate)
        }
        let a = try library.records().map(\.id)
        let b = try library.records().map(\.id)
        #expect(a == b)
    }

    @Test("files the app did not write are ignored, not fatal")
    func foreignFilesIgnored() throws {
        let root = temporaryRoot()
        let library = makeLibrary(root)
        try library.save(imageData: Data([1]), prompt: "ours", seed: 1, aspect: .phone, createdAt: fixedDate)
        // The folder is visible in Files. Users drop things in it.
        try Data("not ours".utf8).write(to: root.appendingPathComponent("notes.txt"))
        try Data().write(to: root.appendingPathComponent("holiday.pdf"))
        let records = try library.records()
        #expect(records.count == 1)
        #expect(records.first?.prompt == "ours")
    }

    @Test("a half-synced pair — image without sidecar, or sidecar without image — is skipped")
    func halfSyncedPairsSkipped() throws {
        let root = temporaryRoot()
        let library = makeLibrary(root)
        try library.save(imageData: Data([1]), prompt: "complete", seed: 1, aspect: .phone, createdAt: fixedDate)

        try Data([9]).write(to: root.appendingPathComponent("2026-01-01T00-00-00Z-aaaaaa.png"))
        try Data("{}".utf8).write(to: root.appendingPathComponent("2026-01-02T00-00-00Z-bbbbbb.json"))

        let records = try library.records()
        #expect(records.count == 1, "got \(records.map(\.id))")
        #expect(records.first?.prompt == "complete")
    }

    @Test("a corrupt sidecar drops one wallpaper, never the whole gallery")
    func corruptSidecarIsolated() throws {
        let root = temporaryRoot()
        let library = makeLibrary(root)
        try library.save(imageData: Data([1]), prompt: "good", seed: 1, aspect: .phone, createdAt: fixedDate)
        let broken = WallpaperFilename.stem(createdAt: fixedDate.addingTimeInterval(60), seed: 2)
        try Data([9]).write(to: root.appendingPathComponent(WallpaperFilename.imageName(broken)))
        try Data("{ this is not json".utf8)
            .write(to: root.appendingPathComponent(WallpaperFilename.sidecarName(broken)))

        let records = try library.records()
        #expect(records.count == 1)
        #expect(records.first?.prompt == "good")
    }

    @Test("delete removes both files and is safe to repeat")
    func deleteIsIdempotent() throws {
        let library = makeLibrary()
        let saved = try library.save(imageData: Data([1]), prompt: "gone soon",
                                     seed: 1, aspect: .phone, createdAt: fixedDate)
        try library.delete(id: saved.id)
        #expect(try library.records().isEmpty)
        try library.delete(id: saved.id)      // a delete interrupted half-way must be completable
        #expect(try library.records().isEmpty)
    }

    @Test("an empty or missing folder lists nothing rather than throwing")
    func emptyGallery() throws {
        let library = makeLibrary()
        #expect(try library.records().isEmpty)
        let missing = WallpaperLibrary(root: temporaryRoot().appendingPathComponent("never-created"))
        #expect(try missing.records().isEmpty)
    }

    @Test("the same code over two different roots behaves identically — the iCloud on/off axis")
    func twoRootsBehaveTheSame() throws {
        let cloudish = makeLibrary()
        let localish = makeLibrary()
        for library in [cloudish, localish] {
            try library.save(imageData: Data([7]), prompt: "same everywhere",
                             seed: 7, aspect: .pad, createdAt: fixedDate)
        }
        let a = try cloudish.records()
        let b = try localish.records()
        #expect(a.count == b.count)
        #expect(a.first?.id == b.first?.id)
        #expect(a.first?.prompt == b.first?.prompt)
        #expect(a.first?.aspect == b.first?.aspect)
        // Only the location differs.
        #expect(a.first?.imageURL != b.first?.imageURL)
    }

    @Test("every offered aspect survives the sidecar")
    func everyAspectRoundTrips() throws {
        let library = makeLibrary()
        for (index, aspect) in AspectRatio.offered.enumerated() {
            try library.save(imageData: Data([UInt8(index)]), prompt: aspect.displayName,
                             seed: UInt32(index), aspect: aspect,
                             createdAt: fixedDate.addingTimeInterval(TimeInterval(index * 60)))
        }
        let byPrompt = Dictionary(uniqueKeysWithValues: try library.records().map { ($0.prompt, $0.aspect) })
        for aspect in AspectRatio.offered {
            #expect(byPrompt[aspect.displayName] == aspect)
        }
    }

    @Test("prompts with quotes, newlines and emoji survive the sidecar unaltered")
    func awkwardPrompts() throws {
        let library = makeLibrary()
        let awkward = "a “paper” crane 🕊\nbacklit, \"macro\" — 100% \\ok/"
        let saved = try library.save(imageData: Data([1]), prompt: awkward,
                                     seed: 1, aspect: .phone, createdAt: fixedDate)
        #expect(try library.record(id: saved.id).prompt == awkward)
    }

    @Test("the sidecar on disk is readable JSON, because the user can open this folder")
    func sidecarIsHumanReadable() throws {
        let library = makeLibrary()
        let saved = try library.save(imageData: Data([1]), prompt: "legible",
                                     seed: 1, aspect: .phone, createdAt: fixedDate)
        let text = try String(contentsOf: saved.sidecarURL, encoding: .utf8)
        #expect(text.contains("\"prompt\""))
        #expect(text.contains("legible"))
        #expect(text.contains("\n"), "pretty-printed, not one long line")
    }

    @Test("asking for a wallpaper that is not there is an error, not a crash")
    func missingRecord() throws {
        let library = makeLibrary()
        #expect(throws: LibraryError.self) { try library.record(id: "nope") }
    }
}
