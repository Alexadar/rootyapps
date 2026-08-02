// On-device icon generator using Apple's ImagePlayground (ImageCreator) foundational image model.
// Usage: swift tools/genicon.swift <output.png>
import Foundation
import ImagePlayground
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "liquid_icon.icon/Assets/1024.png"

let prompt = """
A minimalist celestial app icon: concentric planetary orbit rings on a deep indigo \
night sky, a small bright planet on the outer ring and a glowing sun at the center, \
clean geometric vector style, soft glow, no text.
"""

func save(_ cg: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fputs("could not create destination\n", stderr); exit(2)
    }
    CGImageDestinationAddImage(dest, cg, nil)
    CGImageDestinationFinalize(dest)
}

@main
struct Gen {
    static func main() async {
        do {
            let creator = try await ImageCreator()
            let styles = creator.availableStyles
            fputs("available styles: \(styles)\n", stderr)
            let style = styles.first { "\($0)".lowercased().contains("illustration") } ?? styles.first!
            let stream = creator.images(for: [.text(prompt)], style: style, limit: 1)
            for try await image in stream {
                save(image.cgImage, to: outPath)
                fputs("OK: wrote \(outPath)\n", stderr)
                exit(0)
            }
            fputs("no image produced\n", stderr); exit(3)
        } catch {
            fputs("ImageCreator unavailable: \(error)\n", stderr); exit(1)
        }
    }
}
