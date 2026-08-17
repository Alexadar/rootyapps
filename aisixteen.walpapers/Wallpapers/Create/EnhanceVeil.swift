import SwiftUI

/// The picture reporting on itself while Enhance rewrites it.
///
/// ### The tile grid *is* the progress indicator
///
/// A refinement works in squares, so the honest indicator is the squares themselves: each finished
/// tile's veil clears in place, and the user watches detail arrive where it lands. It is spatially
/// true in a way no capsule can be, and it costs nothing extra to know — the count is already there.
///
/// ### Even cells, not the refiner's real origins
///
/// `TileRefiner`'s grid overlaps heavily: at 1024 the origins are 0, 448 and 512 per axis, because
/// the last one is pulled back to keep the final tile full. Drawn literally, the first tile would
/// clear two-thirds of the picture and the rest would barely move. So the veil partitions the
/// displayed rect **evenly**. It is a small lie about where the work happens and a large truth about
/// how much of it is done, and the user cannot perceive the difference.
///
/// ### It draws no glass
///
/// Deliberately. The result frame already spends `glassEffectID("job")`, and a second glass object
/// inside it would be a duplicate identity in one container — the silent-degradation failure the
/// morph's own notes warn about. A veil made of plain fills has no identity to collide with.
enum EnhanceVeilGrid {

    /// The rect an aspect-fitted image actually occupies inside its container.
    ///
    /// Needed because the two doors present the picture differently: the Create result fills and
    /// clips (so the displayed rect *is* the container), while the Gallery detail sheet fits (so it
    /// is not). Veiling the container in the second case would draw cells over the letterbox.
    static func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (container.width - size.width) / 2,
                      y: (container.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// Columns and rows for `total` tiles.
    ///
    /// Three columns whenever the total divides by three, because the refiner's x axis is always the
    /// fixed 1024 working side — `origins(span: 1024, tile: 512, step: 448)` is three for every
    /// wallpaper this app makes. Rows follow. Anything else falls back to a near-square grid rather
    /// than guessing, so a future tiling change degrades into something sensible instead of
    /// something wrong.
    static func partition(total: Int) -> (columns: Int, rows: Int) {
        guard total > 1 else { return (1, 1) }
        if total % 3 == 0 { return (3, total / 3) }
        let columns = Int(Double(total).squareRoot().rounded(.up))
        return (columns, Int((Double(total) / Double(columns)).rounded(.up)))
    }

    /// The cells, in working order — left to right, top to bottom, matching `TileRefiner.grid`.
    static func cells(in rect: CGRect, columns: Int, rows: Int) -> [CGRect] {
        guard columns > 0, rows > 0 else { return [] }
        let width = rect.width / CGFloat(columns)
        let height = rect.height / CGFloat(rows)
        return (0..<rows).flatMap { row in
            (0..<columns).map { column in
                CGRect(x: rect.minX + CGFloat(column) * width,
                       y: rect.minY + CGFloat(row) * height,
                       width: width, height: height)
            }
        }
    }
}

struct EnhanceVeil: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.wpAccessibility) private var accessibility

    /// Tiles finished. `done == k` means the first k cells in working order are complete — true on
    /// the resume path too, because restored tiles increment the same counter in grid order before
    /// any new tile renders.
    var done: Int
    var total: Int
    /// `nil` when the picture fills its container; the image's own size when it is fitted.
    var imageSize: CGSize?

    var body: some View {
        GeometryReader { proxy in
            let rect = imageSize.map {
                EnhanceVeilGrid.fittedRect(imageSize: $0, in: proxy.size)
            } ?? CGRect(origin: .zero, size: proxy.size)
            let grid = EnhanceVeilGrid.partition(total: total)
            let cells = EnhanceVeilGrid.cells(in: rect, columns: grid.columns, rows: grid.rows)

            ZStack(alignment: .topLeading) {
                ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                    cellView(index: index)
                        .frame(width: cell.width, height: cell.height)
                        .offset(x: cell.minX, y: cell.minY)
                }
            }
            // Crossfades at final positions with zero travel — which is what Reduce Motion permits,
            // so the duration stands in both modes.
            .animation(.easeOut(duration: 0.3), value: done)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func cellView(index: Int) -> some View {
        let cleared = index < done
        let working = index == done

        Rectangle()
            // The same wash the forming picture uses, so the two veils read as one idea. NOT an
            // opaque plate under Reduce Transparency: "nothing opaque over the picture" is the
            // stronger of the two rules, so the tint stays and a hairline carries the partition.
            .fill(Color.white.opacity(accessibility.reduceTransparency ? 0.32 : 0.22))
            .overlay {
                if working {
                    Rectangle()
                        .strokeBorder(WP.accent.opacity(0.35), lineWidth: 1)
                } else if accessibility.reduceTransparency {
                    Rectangle()
                        .strokeBorder(WP.hairline(scheme, opaque: true), lineWidth: 0.5)
                }
            }
            .opacity(cleared ? 0 : 1)
    }
}
