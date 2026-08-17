import SwiftUI
import CoreGraphics
import RecipeKit

/// Painting the Brush scope, over the photo.
///
/// Only present while `Brush` is the selected scope, so the press-and-hold comparison keeps working
/// everywhere else. That ordering is the whole design decision here: comparison is available in
/// every state *except* while the finger is being used to paint, where it would be ambiguous.
struct BrushOverlay: View {

    @Environment(\.colorScheme) private var scheme

    var model: EditModel
    /// The photo's frame inside the view, so a stroke lands where the user actually touched.
    @State private var isErasing = false
    @State private var brushRadius: Double = 48

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                // ⚠️ Converted to **photo pixels**, not left in view points. A
                                // stroke has to mean the same thing on a 402 pt phone and a 1400 pt
                                // Mac window, and the mask is stored at the photo's resolution.
                                let point = Self.photoPoint(value.location,
                                                            in: proxy.size,
                                                            photoWidth: model.original.width,
                                                            photoHeight: model.original.height)
                                model.paintBrush(at: [point],
                                                 radius: brushRadius * Self.scale(in: proxy.size,
                                                                                  photoWidth: model.original.width,
                                                                                  photoHeight: model.original.height),
                                                 erasing: isErasing)
                            }
                    )
                    .accessibilityIdentifier("brush.canvas")
                    .accessibilityLabel("Brush area")
                    .accessibilityHint("Drag to paint the area you want enhanced")

                controls
                    .padding(.bottom, ST.Space.tight)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: ST.Space.gap) {
            Button {
                isErasing.toggle()
            } label: {
                Label(isErasing ? "Erasing" : "Painting",
                      systemImage: isErasing ? "eraser" : "paintbrush.pointed")
                    .stFont(.control)
                    .foregroundStyle(isErasing ? .white : ST.ink(scheme))
                    .padding(.horizontal, ST.Space.gap)
                    .frame(height: ST.compactPillHeight)
                    .background { if isErasing { Capsule().fill(ST.accent) } }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("brush.mode")

            Slider(value: $brushRadius, in: 12...140) {
                Text("Brush size")
            }
            .frame(width: 140)
            .tint(ST.accent)
            .accessibilityIdentifier("brush.size")
        }
        .padding(.horizontal, ST.Space.tight)
        .padding(.vertical, ST.Space.hair)
        .stGlassCapsule(.regular)
    }

    /// How many photo pixels one point covers, for the aspect-fitted photo.
    private static func scale(in size: CGSize, photoWidth: Int, photoHeight: Int) -> Double {
        let fit = min(size.width / Double(photoWidth), size.height / Double(photoHeight))
        return fit > 0 ? 1 / fit : 1
    }

    /// View point → photo pixel, honouring the letterboxing that `.fit` introduces. Without the
    /// offset, every stroke on a photo that does not exactly match the view's aspect lands
    /// systematically off to one side.
    private static func photoPoint(_ point: CGPoint,
                                   in size: CGSize,
                                   photoWidth: Int,
                                   photoHeight: Int) -> CGPoint {
        let fit = min(size.width / Double(photoWidth), size.height / Double(photoHeight))
        guard fit > 0 else { return .zero }
        let drawnWidth = Double(photoWidth) * fit
        let drawnHeight = Double(photoHeight) * fit
        let offsetX = (size.width - drawnWidth) / 2
        let offsetY = (size.height - drawnHeight) / 2
        return CGPoint(x: (point.x - offsetX) / fit, y: (point.y - offsetY) / fit)
    }
}
