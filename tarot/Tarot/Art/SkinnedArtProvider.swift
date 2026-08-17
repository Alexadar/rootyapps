import CoreGraphics
import CoreText
import Foundation
import TarotKit

/// The one interpreter of `SkinSpec`s: renders faces and backs as background + typography —
/// lattice, borders, rules and text, deliberately no pictorial imagery (owner, 2026-08-17).
/// All of it is original procedural drawing; nothing is derived from any published deck's
/// art. A new skin is a new spec, never a fork of this file.
@MainActor
final class SkinnedArtProvider: CardArtProvider {

    let skin: any CardSkin

    private var cache: [String: CardArt] = [:]
    private var cachedBack: CardArt?

    // Face canvas: 512 × 880 (the ~0.58 aspect of a tarot card).
    private let width = 512
    private let height = 880

    init(skin: any CardSkin = Skins.standard) {
        self.skin = skin
    }

    func art(for card: Card, deck: Deck) -> CardArt {
        let key = "\(deck.id)/\(card.id)"
        if let hit = cache[key] { return hit }
        let art = drawFace(card, deck: deck)
        cache[key] = art
        return art
    }

    func backArt() -> CardArt {
        if let cachedBack { return cachedBack }
        let back = drawBack()
        cachedBack = back
        return back
    }

    // MARK: - Canvas

    private func context() -> CGContext {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // RealityKit's generatePlane UVs, CGContext's bottom-left origin, and the card's
        // flip-from-facedown mounting compose to a half-turn-plus-mirror against the naive
        // drawing. Both flips together (a 180° rotation plus the handedness swap) put the
        // rendered face upright and readable — established empirically in the simulator:
        // unmirrored drawing showed "owT", a horizontal-only mirror showed everything
        // upside-down, this shows "Two" at the top of the card. One transform here keeps
        // face, back and foil mask aligned in the same space.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        return ctx
    }

    // MARK: - Text

    private func makeLine(_ string: String, size: CGFloat, color: CGColor) -> CTLine {
        let font = CTFontCreateWithName("Georgia" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    }

    private func lineWidth(_ line: CTLine) -> CGFloat {
        CTLineGetBoundsWithOptions(line, .useOpticalBounds).width
    }

    private func drawText(_ ctx: CGContext, _ string: String, size: CGFloat,
                          color: CGColor, centerX: CGFloat, baselineY: CGFloat) {
        let line = makeLine(string, size: size, color: color)
        ctx.textPosition = CGPoint(x: centerX - lineWidth(line) / 2, y: baselineY)
        CTLineDraw(line, ctx)
    }

    /// Localized names wrap ("The High Priestess", "Die Hohepriesterin") and CJK names
    /// don't break on spaces — so: greedy word wrap where spaces exist, then a uniform
    /// shrink so the widest line fits. Returns the lines it drew (for callers that care).
    private func drawWrapped(_ ctx: CGContext, _ string: String, size: CGFloat,
                             color: CGColor, centerX: CGFloat, centerY: CGFloat,
                             maxWidth: CGFloat, maxLines: Int = 3) {
        let words = string.split(separator: " ").map(String.init)
        var lines: [String] = []
        if words.count <= 1 {
            lines = [string]
        } else {
            var current = ""
            for word in words {
                let candidate = current.isEmpty ? word : current + " " + word
                if lineWidth(makeLine(candidate, size: size, color: color)) <= maxWidth || current.isEmpty {
                    current = candidate
                } else {
                    lines.append(current)
                    current = word
                }
            }
            lines.append(current)
            // Too many lines: merge the tail rather than drop it; the shrink pass saves it.
            while lines.count > maxLines {
                let last = lines.removeLast()
                lines[lines.count - 1] += " " + last
            }
        }
        let widest = lines.map { lineWidth(makeLine($0, size: size, color: color)) }.max() ?? 1
        let fitted = widest > maxWidth ? size * maxWidth / widest : size
        let lineHeight = fitted * 1.22
        let firstBaseline = centerY + lineHeight * CGFloat(lines.count - 1) / 2
        for (i, text) in lines.enumerated() {
            drawText(ctx, text, size: fitted, color: color,
                     centerX: centerX, baselineY: firstBaseline - lineHeight * CGFloat(i))
        }
    }

    // MARK: - Ornament

    private func fill(_ ctx: CGContext, _ color: CGColor) {
        ctx.setFillColor(color)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }

    private func lattice(_ ctx: CGContext, color: CGColor, spacing: CGFloat, lineWidth: CGFloat) {
        let w = CGFloat(width), h = CGFloat(height)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(lineWidth)
        var offset: CGFloat = -h
        while offset < w + h {
            ctx.move(to: CGPoint(x: offset, y: 0))
            ctx.addLine(to: CGPoint(x: offset + h, y: h))
            ctx.move(to: CGPoint(x: offset + h, y: 0))
            ctx.addLine(to: CGPoint(x: offset, y: h))
            offset += spacing
        }
        ctx.strokePath()
    }

    private func strokeBorder(_ ctx: CGContext, color: CGColor, inset: CGFloat, lineWidth: CGFloat) {
        ctx.setStrokeColor(color)
        ctx.setLineWidth(lineWidth)
        ctx.stroke(CGRect(x: inset, y: inset,
                          width: CGFloat(width) - 2 * inset, height: CGFloat(height) - 2 * inset))
    }

    private func rule(_ ctx: CGContext, color: CGColor, y: CGFloat, halfSpan: CGFloat) {
        let w = CGFloat(width)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: w / 2 - halfSpan, y: y))
        ctx.addLine(to: CGPoint(x: w / 2 + halfSpan, y: y))
        ctx.strokePath()
    }

    private static let romanNumerals = [
        "0", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI",
        "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX", "XX", "XXI",
    ]

    // MARK: - Faces

    private func drawFace(_ card: Card, deck: Deck) -> CardArt {
        let spec = skin.spec
        let ctx = context()
        let w = CGFloat(width), h = CGFloat(height)

        switch card {
        case .major(let n):
            let gold = spec.majorAccent
            fill(ctx, spec.faceBackground.cg)
            lattice(ctx, color: gold.alpha(spec.faceLatticeAlpha),
                    spacing: spec.faceLatticeSpacing, lineWidth: 2)
            strokeBorder(ctx, color: gold.cg, inset: 18, lineWidth: 6)
            strokeBorder(ctx, color: gold.alpha(0.5), inset: 34, lineWidth: 2)
            let numeral = Self.romanNumerals.indices.contains(n) ? Self.romanNumerals[n] : String(n)
            drawText(ctx, numeral, size: 76, color: gold.cg, centerX: w / 2, baselineY: h - 160)
            rule(ctx, color: gold.alpha(0.6), y: h - 120, halfSpan: 70)
            drawWrapped(ctx, L.loc(deck.name(for: card)), size: 68, color: gold.cg,
                        centerX: w / 2, centerY: h / 2 - 20, maxWidth: w - 130)
            rule(ctx, color: gold.alpha(0.6), y: 120, halfSpan: 70)

        case .minor(let suit, let rank):
            let accent = spec.accent(for: suit)
            fill(ctx, spec.faceBackground.cg)
            lattice(ctx, color: accent.alpha(spec.faceLatticeAlpha),
                    spacing: spec.faceLatticeSpacing, lineWidth: 2)
            strokeBorder(ctx, color: accent.cg, inset: 18, lineWidth: 5)
            strokeBorder(ctx, color: accent.alpha(0.5), inset: 32, lineWidth: 2)
            let rankWord = rank == .page ? deck.pageTitle : rank.displayName
            drawText(ctx, L.loc(rankWord), size: 54, color: accent.cg,
                     centerX: w / 2, baselineY: h - 156)
            rule(ctx, color: accent.alpha(0.6), y: h - 118, halfSpan: 56)
            drawWrapped(ctx, L.loc(deck.name(for: card)), size: 56, color: spec.faceInk.cg,
                        centerX: w / 2, centerY: h / 2 - 20, maxWidth: w - 130)
            rule(ctx, color: accent.alpha(0.6), y: 120, halfSpan: 56)
        }

        let face = ctx.makeImage()!
        return CardArt(face: face, foilMask: drawFoilMask(card), isMajor: card.arcana == .major)
    }

    /// R = where foil lives, G = film thickness variation, B = fine relief lines.
    private func drawFoilMask(_ card: Card) -> CGImage {
        let ctx = context()
        let w = CGFloat(width), h = CGFloat(height)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let isMajor = card.arcana == .major
        if isMajor {
            // Foil rings — but the text-only faces (2026-08-17) need a calm window where
            // the name sits: rings first, then the center band is wiped back to no-foil.
            let steps = 24
            for i in 0..<steps {
                let t = CGFloat(i) / CGFloat(steps - 1)
                let inset = 20 + t * 190
                let thickness = 0.35 + 0.6 * (0.5 + 0.5 * sin(t * 12))
                // R = 0.4: with type instead of art on the face, 0.6 buried the name (seen).
                ctx.setStrokeColor(CGColor(red: 0.4, green: thickness, blue: t, alpha: 1))
                ctx.setLineWidth(16)
                ctx.stroke(CGRect(x: inset, y: inset * (h / w), width: w - 2 * inset,
                                  height: h - 2 * inset * (h / w)))
            }
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: 64, y: h / 2 - 190, width: w - 128, height: 380))
        } else {
            // Border foil + a whisper of lattice shimmer — the old glyph-pool ellipse read
            // as a rainbow blotch behind the name once faces went text-only (seen, fixed).
            ctx.setStrokeColor(CGColor(red: 1.0, green: 0.6, blue: 0.3, alpha: 1))
            ctx.setLineWidth(22)
            ctx.stroke(CGRect(x: 20, y: 20, width: w - 40, height: h - 40))
            lattice(ctx, color: CGColor(red: 0.30, green: 0.5, blue: 0.4, alpha: 1),
                    spacing: skin.spec.faceLatticeSpacing, lineWidth: 2)
        }
        return ctx.makeImage()!
    }

    // MARK: - Back

    private func drawBack() -> CardArt {
        let spec = skin.spec
        let ctx = context()
        let w = CGFloat(width), h = CGFloat(height)
        // Dense lattice + emblem: instantly distinct from any face (which carries a much
        // fainter weave and big type instead).
        fill(ctx, spec.backBackground.cg)
        lattice(ctx, color: spec.backAccent.alpha(0.45), spacing: spec.backLatticeSpacing, lineWidth: 3)
        strokeBorder(ctx, color: spec.backAccent.cg, inset: 16, lineWidth: 8)
        drawText(ctx, spec.backEmblem, size: 220, color: spec.backAccent.cg,
                 centerX: w / 2, baselineY: h / 2 - 70)
        let back = ctx.makeImage()!

        // The back gets a quiet lattice-shaped foil so tilting the deck already shimmers.
        let maskCtx = context()
        maskCtx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        maskCtx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        maskCtx.setStrokeColor(CGColor(red: 0.5, green: 0.4, blue: 0.2, alpha: 1))
        maskCtx.setLineWidth(3)
        var offset: CGFloat = -h
        while offset < w + h {
            maskCtx.move(to: CGPoint(x: offset, y: 0))
            maskCtx.addLine(to: CGPoint(x: offset + h, y: h))
            offset += spec.backLatticeSpacing
        }
        maskCtx.strokePath()
        let art = CardArt(face: back, foilMask: maskCtx.makeImage()!, isMajor: false)
        return art
    }
}
