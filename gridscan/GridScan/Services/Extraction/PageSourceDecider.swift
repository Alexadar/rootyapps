import Foundation
import CoreGraphics

/// Per-PAGE branch: born-digital text layer vs OCR. Never per file. A usable text layer
/// is NOT `page.string != nil` — bad prior OCR leaves a garbage layer that must be
/// detected and re-OCR'd. Pure function over extracted stats; golden-tested.
enum PageSource: Equatable {
    case textLayer
    case ocr(OCRReason)

    enum OCRReason: String {
        case noTextLayer = "no text layer"
        case garbageLayer = "garbage text layer"
        case imageWithTokenText = "image with token text"
    }

    var auditDescription: String {
        switch self {
        case .textLayer: return "text layer"
        case .ocr(let reason): return "OCR (\(reason.rawValue))"
        }
    }
}

struct PageSourceThresholds {
    var minimumChars = 24
    var maxReplacementRatio = 0.01
    var maxControlRatio = 0.02
    var minAlnumRatio = 0.55
    var maxJunkTokenRatio = 0.30
    var maxSingleCharTokenRatio = 0.40
    var tokenLengthRange = 1.5...20.0
    var maxDegenerateBoundsRatio = 0.15
    var sparseCoverageMax = 0.005          // union of word boxes / page area
    var sparseCharsMax = 200

    static let standard = PageSourceThresholds()
}

enum PageSourceDecider {

    /// `wordBounds` are sampled word bounds in PDF points (cropBox space); pass what the
    /// adapter cheaply sampled (≤ ~40). Pure — callers gather the inputs.
    static func decide(text rawText: String?,
                       wordBounds: [CGRect],
                       cropBox: CGRect,
                       thresholds t: PageSourceThresholds = .standard) -> PageSource {
        guard let text = rawText?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.count >= t.minimumChars else {
            return .ocr(.noTextLayer)
        }

        let scalars = text.unicodeScalars
        let total = scalars.count
        let replacement = scalars.filter { $0 == "\u{FFFD}" }.count
        if Double(replacement) / Double(total) > t.maxReplacementRatio {
            return .ocr(.garbageLayer)
        }
        let control = scalars.filter {
            $0.properties.generalCategory == .control && $0 != "\n" && $0 != "\t" && $0 != "\r"
        }.count
        if Double(control) / Double(total) > t.maxControlRatio {
            return .ocr(.garbageLayer)
        }
        let nonWhitespace = scalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
        let alnum = nonWhitespace.filter { CharacterSet.alphanumerics.contains($0) }.count
        if !nonWhitespace.isEmpty,
           Double(alnum) / Double(nonWhitespace.count) < t.minAlnumRatio {
            return .ocr(.garbageLayer)
        }

        let tokens = text.split(whereSeparator: { $0.isWhitespace })
        if !tokens.isEmpty {
            let junk = tokens.filter { tok in
                !tok.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
            }.count
            if Double(junk) / Double(tokens.count) > t.maxJunkTokenRatio {
                return .ocr(.garbageLayer)
            }
            let singles = tokens.filter { $0.count == 1 && !($0.first?.isNumber ?? false)
                && !["a", "i", "A", "I"].contains(String($0)) }.count
            if Double(singles) / Double(tokens.count) > t.maxSingleCharTokenRatio {
                return .ocr(.garbageLayer)
            }
            let avgLen = Double(tokens.reduce(0) { $0 + $1.count }) / Double(tokens.count)
            if !t.tokenLengthRange.contains(avgLen) {
                return .ocr(.garbageLayer)
            }
        }

        // Geometry cross-check — plausible-looking prior OCR with broken bounds.
        if !wordBounds.isEmpty {
            let degenerate = wordBounds.filter {
                $0.width <= 0 || $0.height <= 0 || !cropBox.insetBy(dx: -2, dy: -2).intersects($0)
            }.count
            if Double(degenerate) / Double(wordBounds.count) > t.maxDegenerateBoundsRatio {
                return .ocr(.garbageLayer)
            }
            // A stamp/header on a full-page scan: tiny coverage, short text.
            if text.count < t.sparseCharsMax, cropBox.width > 0, cropBox.height > 0 {
                let coverage = wordBounds.reduce(0.0) { $0 + Double($1.width * $1.height) }
                    / Double(cropBox.width * cropBox.height)
                if coverage < t.sparseCoverageMax {
                    return .ocr(.imageWithTokenText)
                }
            }
        }
        return .textLayer
    }
}
