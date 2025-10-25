import Foundation
import SpriteKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Texture Loading Utilities
extension Monster {

    /// Utility: load textures from a folder inside bundle (e.g. "monsters/berserker/walk").
    /// Robust: tries inDirectory first, then falls back to scanning all PNGs and matching by filename prefix
    /// (useful because Xcode may copy resources flattened into the bundle root).
    func loadTextures(fromDirectory subpath: String) -> [SKTexture] {
        var textures: [SKTexture] = []

        // 1) Try to load resources from the exact directory inside the bundle.
        var rawPaths = Bundle.main.paths(forResourcesOfType: "png", inDirectory: subpath)

        // 2) Fallback: if nothing found, try to match by filename prefix.
        if rawPaths.isEmpty {
            // Derive a filename prefix from the last path component, e.g. "monsters/berserker/walk" -> "walk_"
            let comp = subpath.components(separatedBy: "/").last ?? subpath
            let prefix = comp + "_"

            // Scan all PNGs in the bundle root and filter by prefix
            let allPngs = Bundle.main.paths(forResourcesOfType: "png", inDirectory: nil)
            rawPaths = allPngs.filter { path in
                let name = (path as NSString).lastPathComponent
                return name.hasPrefix(prefix)
            }
        }

        // Sort by filename numerically (extract number from filename like "walk_12.png" -> 12)
        let sortedPaths = rawPaths.sorted { (a, b) -> Bool in
            let nameA = (a as NSString).lastPathComponent
            let nameB = (b as NSString).lastPathComponent

            // Extract numeric part from filename (e.g., "walk_12.png" -> 12)
            let numA = nameA.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .compactMap { Int($0) }
                .first ?? 0
            let numB = nameB.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .compactMap { Int($0) }
                .first ?? 0

            return numA < numB
        }

        for p in sortedPaths {
#if os(macOS)
            if let img = NSImage(contentsOfFile: p) {
                let tex = SKTexture(image: img)
                textures.append(tex)
            }
#else
            if let uiImg = UIImage(contentsOfFile: p) {
                let tex = SKTexture(image: uiImg)
                textures.append(tex)
            }
#endif
        }

        return textures
    }
}
