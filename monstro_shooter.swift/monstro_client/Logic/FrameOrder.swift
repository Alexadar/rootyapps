import Foundation

/// Pure animation-frame ordering extracted from `Monster.loadTextures`.
/// Frame names look like "Bird5/dying_01"; splitting on non-digits yields [5, 1],
/// so the LAST number is the frame index (the first is the monster ID).
enum FrameOrder {
    /// Extract the frame number from a texture name (the last numeric run), defaulting to 0.
    static func frameNumber(from name: String) -> Int {
        name.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { Int($0) }
            .last ?? 0
    }

    /// Sort texture names by ascending frame number.
    static func sortedFrameNames(_ names: [String]) -> [String] {
        names.sorted { frameNumber(from: $0) < frameNumber(from: $1) }
    }
}
