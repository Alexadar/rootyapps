import DirectionKit
import FormatKit
import ProjectKit
import SwiftUI

/// Result — the proposal.
///
/// A before/after pair, not an edited image. That distinction is the whole 4.3 separation from
/// Studio: Studio blends one photograph by degree, this one shows you two futures for a space.
struct ResultView: View {

    let project: SpaceProject
    let variationIndex: Int
    @Bindable var model: ResultModel
    var layout: SheetSurface<AnyView>.Layout = .sheet

    let onSelectVariation: (Int) -> Void
    let onNewVariation: () -> Void
    let onSave: () -> Void
    let onTryAgain: () -> Void
    let onShare: () -> Void
    let onRegenerate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        switch layout {
        case .sheet:
            VStack(spacing: 0) {
                comparison
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                SheetSurface(layout: .sheet) { AnyView(controls) }
            }
            .background(ARC.canvas)
        case .rail:
            HStack(spacing: 0) {
                comparison
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                SheetSurface(layout: .rail) { AnyView(controls) }
            }
            .background(ARC.canvas)
        }
    }

    private var styleName: String {
        project.sidecar?.recipe.presetID
            .flatMap { PresetCatalog.preset(id: $0)?.name } ?? "Redesign"
    }

    private var current: VariationRecord? {
        project.variations.first { $0.index == variationIndex } ?? project.variations.first
    }

    // ── the comparison ───────────────────────────────────────────────────────────────────────

    private var comparison: some View {
        WipeComparison(model: model, styleName: styleName) {
            FileImage(url: project.sourceURL, maxPixel: 2048)
        } after: {
            if let current, current.imageIsPresent {
                FileImage(url: current.imageURL, maxPixel: 2048)
            } else {
                LinearGradient(colors: [Color(hex: 0xF0EBE2), Color(hex: 0xC4AC82)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
    }

    // ── the controls ─────────────────────────────────────────────────────────────────────────

    @ViewBuilder private var controls: some View {
        VStack(spacing: ARC.Space.grid) {
            variantStrip
            actionRow
        }
    }

    private var variantStrip: some View {
        HStack(spacing: ARC.Space.tight) {
            ForEach(project.variations) { variation in
                Button { onSelectVariation(variation.index) } label: {
                    variantThumbnail(variation)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("result.variant.\(variation.index)")
                .accessibilityLabel("Variation \(variation.index)")
                .accessibilityAddTraits(variation.index == variationIndex ? [.isSelected, .isButton] : .isButton)
            }

            AddTile(label: "New variation",
                    width: 56, height: 42,
                    identifier: "result.newvariation",
                    action: onNewVariation)

            Spacer(minLength: ARC.Space.tight)

            Text(VariationText.done(project.finishedCount,
                                    of: max(project.sidecar?.recipe.requestedVariations ?? 0,
                                            project.variations.count)))
                .arcText(.caption, tabularNumbers: true)
                .foregroundStyle(ARC.ink.opacity(0.55))
                .accessibilityIdentifier("result.tally")
        }
    }

    private func variantThumbnail(_ variation: VariationRecord) -> some View {
        Group {
            if variation.imageIsPresent {
                FileImage(url: variation.imageURL, maxPixel: 160)
            } else {
                // Not yet downloaded from another device. A real state, not a broken tile.
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(ARC.canvasAlt)
                    .overlay {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(ARC.ink.opacity(0.4))
                    }
            }
        }
        .frame(width: 56, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay { SelectionBorder(isSelected: variation.index == variationIndex, radius: 10) }
    }

    private var actionRow: some View {
        HStack(spacing: ARC.Space.tight) {
            PillButton(title: "Save", role: .ink, fillWidth: true, action: onSave)
                .accessibilityIdentifier("result.save")

            Button("Try again", action: onTryAgain)
                .buttonStyle(.glass)
                .frame(minHeight: ARC.minimumHitTarget)
                .accessibilityIdentifier("result.again")
                .accessibilityHint("Regenerates with the same prompt and a new seed")

            Menu {
                Button("Share…", action: onShare)
                Button("Regenerate with edits", action: onRegenerate)
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 52, height: ARC.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .accessibilityIdentifier("result.more")
            .accessibilityLabel("More actions")
        }
    }
}

/// An image from a file, decoded at the size it will be drawn.
///
/// Through ImageIO rather than `Image(contentsOfFile:)`: a library grid that decodes twelve
/// 12-megapixel photos to draw twelve 90-point tiles is how a scroll view runs a device out of
/// memory.
struct FileImage: View {
    let url: URL
    let maxPixel: Int

    @State private var image: PlatformImage?

    var body: some View {
        Group {
            if let image {
                Image(platform: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: [ARC.canvasAlt, Color(hex: 0xC4AC82)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .task(id: url) {
            let url = url
            let maxPixel = maxPixel
            image = await Task.detached(priority: .userInitiated) {
                Bitmap.thumbnail(contentsOf: url, maxPixel: maxPixel)
            }.value
        }
    }
}
