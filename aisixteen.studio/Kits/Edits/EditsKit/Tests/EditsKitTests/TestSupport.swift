import Foundation
@testable import EditsKit

/// Stand-in bytes for an imported photo. Not empty and not uniform, so a truncation or a
/// substitution is genuinely a different hash.
let samplePhoto: Data = Data((0..<4096).map { UInt8(($0 &* 37 &+ 11) % 251) })

let fixedDate = Date(timeIntervalSince1970: 1_786_000_000)   // 2026-08-08, in UTC

func makeTemporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("EditsKitTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func makeLibrary(root: URL? = nil,
                 access: FileAccess = DirectFileAccess(),
                 appVersion: String = "1.0") -> EditLibrary {
    EditLibrary(root: root ?? makeTemporaryDirectory(), access: access, appVersion: appVersion)
}
