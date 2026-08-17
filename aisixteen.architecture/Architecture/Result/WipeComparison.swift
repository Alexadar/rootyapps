import SwiftUI

/// Before and after, with one gesture recogniser.
///
/// The wipe is the recommendation, and the reason is the promise itself: the eye tracks one edge
/// across the divider and sees it *not move*. That is the whole geometric-fidelity claim, made
/// visible. Tap-to-flip and hold-to-peek ride along as secondary.
///
/// ⚠️ TWO REAL DEFECTS IN THE HANDOFF, both fixed here:
///
///  1. `divider(at:)` ended with `.position(x: x, y: 0)` inside a `.frame(maxHeight: .infinity)`,
///     which puts the 44 pt knob's CENTRE on the top edge — half of it off-screen, and an
///     effective hit target of 22 pt, under the accessibility floor it was written to satisfy.
///
///  2. `DragGesture(minimumDistance: 0)`, `.onTapGesture` and `.onLongPressGesture` were stacked
///     on one view. A zero-distance drag claims the touch immediately, so the tap and the long
///     press are unreachable in practice and non-deterministic under XCUITest. There is ONE
///     recogniser here and flip and peek are derived inside it.
///
/// `uitests.md` §6 also applies: appearance is driven by a mask width and `.opacity`, never by an
/// `if` that swaps view identity mid-drag — a drag that does one step and dies is a view changing
/// identity underneath the gesture.
struct WipeComparison<Before: View, After: View>: View {

    @Bindable var model: ResultModel
    let styleName: String
    @ViewBuilder var before: Before
    @ViewBuilder var after: After

    @Environment(\.arcAccessibility) private var accessibility

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack(alignment: .topLeading) {
                before
                    .frame(width: width, height: height)
                    .clipped()

                after
                    .frame(width: width, height: height)
                    .clipped()
                    // A mask, not a conditional subview: the "after" view keeps its identity for
                    // the whole drag, and only what it draws changes.
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: width * model.revealedWidthFraction)
                    }

                divider(width: width, height: height)
                labels
            }
            .contentShape(Rectangle())
            .gesture(gesture(width: width))
        }
        .accessibilityElement()
        .accessibilityIdentifier("result.wipe")
        .accessibilityLabel("Before and after comparison, \(styleName)")
        .accessibilityValue("After revealed, \(model.revealedPercent) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.adjust(revealMore: true)
            case .decrement: model.adjust(revealMore: false)
            @unknown default: break
            }
        }
        .accessibilityHint("Swipe up or down to reveal more. Double-tap to flip.")
    }

    // ── the one gesture ──────────────────────────────────────────────────────────────────────

    private func gesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                model.dragChanged(locationX: value.location.x,
                                  translationX: value.translation.width,
                                  width: width,
                                  reduceMotion: accessibility.reduceMotion)
            }
            .onEnded { value in
                model.dragEnded(translationX: value.translation.width,
                                width: width,
                                reduceMotion: accessibility.reduceMotion)
            }
    }

    // ── the divider ──────────────────────────────────────────────────────────────────────────

    private func divider(width: CGFloat, height: CGFloat) -> some View {
        let x = width * model.wipe
        return ZStack {
            Rectangle()
                .fill(.white)
                .frame(width: 2.5, height: height)
                .shadow(color: .black.opacity(0.35), radius: 6)
                .position(x: x, y: height / 2)

            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(ARC.ink)
                .frame(width: ARC.minimumHitTarget, height: ARC.minimumHitTarget)
                .arcGlass(.regular, in: Circle(), shadow: true)
                // The fix: the knob's centre sits at the vertical CENTRE, not at y = 0.
                .position(x: x, y: height / 2)
                .contentShape(Circle())
                .accessibilityIdentifier("result.knob")
                .accessibilityHidden(true)
        }
        .opacity(model.isPeeking ? 0 : 1)
        .allowsHitTesting(false)
    }

    private var labels: some View {
        HStack {
            Text("Before")
                .arcText(.captionStrong)
                .foregroundStyle(.white)
                .padding(.horizontal, ARC.Space.gap)
                .padding(.vertical, 5)
                .background(Capsule().fill(.black.opacity(0.55)))
                .accessibilityIdentifier("result.label.before")
            Spacer()
            Text("After · \(styleName)")
                .arcText(.captionStrong)
                .foregroundStyle(ARC.ink)
                .padding(.horizontal, ARC.Space.gap)
                .padding(.vertical, 5)
                .arcGlassCapsule(shadow: false)
                .accessibilityIdentifier("result.label.after")
        }
        .padding(ARC.Space.grid)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
