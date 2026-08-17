import SwiftUI
import CoreGraphics
import RecipeKit

/// The photo, with the original one gesture away — in every state, including during the pass.
///
/// Three ways to see the original (`1j`), all live at once:
///
/// 1. **Press-and-hold anywhere.** Release snaps back. The Mac's Space bar routes here too.
/// 2. **The split handle**, draggable edge to edge.
/// 3. **Strength → 0**, handled upstream: the compositor returns the original itself, so this view
///    is simply showing the same picture on both sides.
///
/// ⚠️ The handle is **one** accessibility element, not a slider plus two images. VoiceOver adjusts
/// it in 10 % steps and hears "70 percent enhanced"; every one of those strings comes from
/// `Comparison`, so they are asserted in `swift test` rather than read off a screen.
struct ComparisonView: View {

    @Environment(\.stAccessibility) private var accessibility

    /// The milk veil, while a pass is running.
    ///
    /// ⚠️ It belongs **inside** this view and on the enhanced layer only. Applied to the whole
    /// canvas it also veils the original, and then the split compares mush against mush for the
    /// entire wait — which removes the one thing that makes a tile-by-tile enhance legible, and is
    /// exactly what the board means by "resolves live *against the original split*".
    struct Veil: Equatable {
        /// `rgba(255,255,255,.22)`.
        var opacity: Double
        /// Points, 26 → 0 as tiles land. The board's number, not a fraction of it.
        var blur: Double
    }

    let original: CGImage
    let enhanced: CGImage
    @Binding var comparison: Comparison
    /// Hidden when the two sides are the same picture — a split over one image compares nothing.
    var showsHandle: Bool = true
    var veil: Veil?

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            let height = proxy.size.height
            let split = width * comparison.effectiveRevealed

            ZStack(alignment: .topLeading) {
                // Enhanced underneath, original revealed over it from the left. This way round on
                // purpose: the enhanced picture is the resting state, so it is the one that is whole
                // and never clipped.
                Image(cgImage: enhanced)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: width, height: height)
                    // `opaque: true` keeps the blur from sampling transparent edges and darkening
                    // the frame's border, which reads as a vignette appearing mid-pass.
                    .blur(radius: veil?.blur ?? 0, opaque: true)
                    .overlay(ST.veilWhite.opacity(veil?.opacity ?? 0))
                    .clipped()
                    .animation(.easeInOut(duration: 0.25), value: veil)

                Image(cgImage: original)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: width, height: height)
                    .mask(alignment: .trailing) {
                        Rectangle().frame(width: max(0, width - split))
                    }

                if showsHandle {
                    captions(width: width, split: split)
                    handle(width: width, height: height, x: split)
                }
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            // Press-and-hold **anywhere on the photo**, not only on the handle.
            .gesture(holdGesture)
            .accessibilityElement()
            .accessibilityLabel(comparison.accessibilityLabel)
            .accessibilityValue(comparison.accessibilityValue)
            .accessibilityHint(comparison.accessibilityHint)
            .accessibilityIdentifier("compare.canvas")
            // The whole point of "one adjustable element": swipe up and down move the split.
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: comparison.increment()
                case .decrement: comparison.decrement()
                @unknown default: break
                }
            }
        }
    }

    private var holdGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.12)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                // `.second` means the press was recognised — a tap that never becomes a press does
                // not flash the original, which would read as a glitch rather than a comparison.
                guard case .second = value, !comparison.isHoldingOriginal else { return }
                withAnimation(STMotion.holdOriginal(reduceMotion: accessibility.reduceMotion)) {
                    comparison.isHoldingOriginal = true
                }
            }
            .onEnded { _ in
                withAnimation(STMotion.holdOriginal(reduceMotion: accessibility.reduceMotion)) {
                    comparison.isHoldingOriginal = false
                }
            }
    }

    // MARK: The handle

    private func handle(width: CGFloat, height: CGFloat, x: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(.white)
                .frame(width: ST.handleLineWidth, height: height)
                .shadow(color: .black.opacity(0.35), radius: 3)

            Circle()
                .fill(.white)
                .frame(width: ST.handleGrip, height: ST.handleGrip)
                .overlay {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(ST.accent)
                }
                .shadow(color: .black.opacity(0.28), radius: 5, y: 2)
        }
        // 38 pt of visible grip on a 56 pt target (`1j`). The two numbers are deliberately
        // different; using one for both either looks wrong or fails the 44 pt floor.
        .frame(width: ST.handleTarget, height: height)
        .contentShape(Rectangle())
        .position(x: x, y: height / 2)
        .highPriorityGesture(
            // Direct manipulation, so this is never animated and is deliberately left untouched by
            // Reduce Motion (`1k`). High priority so the handle wins over the hold-anywhere gesture
            // it sits on top of.
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    comparison.isHoldingOriginal = false
                    comparison.setRevealed(value.location.x / width)
                }
        )
        .accessibilityHidden(true)   // the whole canvas is the one adjustable element
    }

    private func captions(width: CGFloat, split: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            caption(Comparison.originalCaption)
                .padding(.leading, ST.Space.grid)
                .padding(.top, ST.Space.grid)
                .opacity(split > 90 ? 1 : 0)

            caption(Comparison.enhancedCaption)
                .padding(.trailing, ST.Space.grid)
                .padding(.top, ST.Space.grid)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .opacity(width - split > 100 ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.15), value: split)
        .accessibilityHidden(true)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .stFont(.splitCaption)
            .tracking(1.2)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black.opacity(0.28), in: Capsule())
    }
}
