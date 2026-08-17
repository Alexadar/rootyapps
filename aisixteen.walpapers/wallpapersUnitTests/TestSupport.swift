import Foundation
import GenerationKit
import LibraryKit
@testable import Wallpapers

/// A record without touching the disk, for tests that only care about what a record carries.
func makeRecord(prompt: String,
                seed: UInt32 = 0x3F9C1A,
                aspect: AspectRatio = .phone,
                createdAt: Date = Date(timeIntervalSince1970: 1_786_000_000)) -> WallpaperRecord {
    let metadata = WallpaperMetadata(prompt: prompt, seed: seed, aspect: aspect,
                                     createdAt: createdAt, appVersion: "1.0.0")
    let stem = WallpaperFilename.stem(createdAt: createdAt, seed: seed)
    let root = FileManager.default.temporaryDirectory
    return WallpaperRecord(id: stem,
                           metadata: metadata,
                           imageURL: root.appendingPathComponent(WallpaperFilename.imageName(stem)),
                           sidecarURL: root.appendingPathComponent(WallpaperFilename.sidecarName(stem)))
}

/// A throwaway directory that cleans up after itself.
func makeTemporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("WallpapersTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
