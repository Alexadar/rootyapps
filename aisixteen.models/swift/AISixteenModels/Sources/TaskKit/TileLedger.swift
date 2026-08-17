import Foundation

/// Which tiles are already done, and which are left.
///
/// The unit of resumption for stages 2 and 3, and the reason those stages are resumable at all:
/// tiles are independent, so "how far did we get" is answerable by looking at the disk. No model
/// state to checkpoint, no partially-denoised latent to serialise — a resumed job simply skips the
/// squares that already have files.
///
/// Deliberately takes a list of filenames rather than reading a directory, so every rule here is
/// testable without touching a disk.
public enum TileLedger {

    /// `tile-007.png`. Zero-padded so the files sort in working order in Finder, which matters the
    /// one time somebody has to look at a half-finished job by hand.
    public static func filename(_ index: Int) -> String {
        String(format: "tile-%03d.png", index)
    }

    /// The indices represented by a directory listing. Anything unrecognised is ignored rather than
    /// treated as an error: the folder may pick up `.DS_Store` or a stray file, and that must not
    /// make a resumable job look corrupt.
    public static func completed(in filenames: [String]) -> Set<Int> {
        Set(filenames.compactMap { name in
            guard name.hasPrefix("tile-"), name.hasSuffix(".png") else { return nil }
            return Int(name.dropFirst(5).dropLast(4))
        })
    }

    /// The tiles still to do, in order, given how many there are in total.
    ///
    /// Indices outside the range are ignored: a ledger left over from a larger grid must not
    /// suppress work in a smaller one. (The manifest already refuses to resume across a grid
    /// change; this is the second line of defence, because the failure would be a silently missing
    /// patch of picture.)
    public static func remaining(total: Int, completed: Set<Int>) -> [Int] {
        guard total > 0 else { return [] }
        return (0..<total).filter { !completed.contains($0) }
    }

    /// How far along, for the resume card. Counts only what is genuinely on disk.
    public static func progress(total: Int, completed: Set<Int>) -> (done: Int, total: Int) {
        (min(completed.filter { $0 >= 0 && $0 < total }.count, total), total)
    }
}
