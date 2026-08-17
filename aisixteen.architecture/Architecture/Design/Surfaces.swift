import SwiftUI

/// The standing control surface over a full-bleed photo.
///
/// The handoff's `GlassSheet`, with the `-DS.rSheet + 8` offset folded in — all three screens that
/// used it repeated that offset at the call site, which is exactly the kind of thing one screen
/// eventually forgets.
///
/// On a regular-width layout it renders as the iPad **direction rail** instead: same body, laid
/// out down the trailing edge rather than across the bottom, so the photo is never covered. Same
/// view, two shapes — which is what stops the phone and the iPad drifting apart.
struct SheetSurface<Content: View>: View {

    enum Layout {
        /// Bottom sheet. Phone, and iPad in Slide Over.
        case sheet
        /// Trailing rail. iPad and Mac at regular width.
        case rail
    }

    var layout: Layout = .sheet
    @ViewBuilder var content: Content

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        switch layout {
        case .sheet:
            content
                .padding(ARC.Space.margin)
                .frame(maxWidth: .infinity)
                .arcGlassSheet()
                .offset(y: -ARC.Radius.sheet + 8)
        case .rail:
            content
                .padding(ARC.Space.margin)
                .frame(width: typeSize >= .accessibility3 ? ARC.railWidthAX : ARC.railWidth,
                       alignment: .top)
                .frame(maxHeight: .infinity, alignment: .top)
                .arcGlassCard(radius: ARC.Radius.card)
                .padding(ARC.Space.grid)
        }
    }
}

/// The white card inside a sheet: preset card, prompt field, variation row, pause card.
struct SheetCard<Content: View>: View {
    var radius: CGFloat = ARC.Radius.preset
    var fill: Double = 0.9
    @ViewBuilder var content: Content

    @Environment(\.arcAccessibility) private var accessibility

    var body: some View {
        content
            .padding(ARC.Space.gap)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    // Under Reduce Transparency the plate is already opaque, so a translucent card
                    // on top of it would be the one thing that still looks like glass.
                    .fill(accessibility.reduceTransparency
                          ? Color.white
                          : Color.white.opacity(fill))
            }
    }
}

/// The milk veil over a forming image: white .22, blur easing 26 → 0 across the run.
///
/// Tokenised and step-driven so Reduce Motion can quantise it into stills, which the handoff asks
/// for and the mockups' hardcoded `26 * (1 - fraction)` could not do.
struct MilkVeil: ViewModifier {
    let step: Int
    let totalSteps: Int

    @Environment(\.arcAccessibility) private var accessibility

    func body(content: Content) -> some View {
        content
            .blur(radius: ARCMotion.veilBlur(atStep: step,
                                             totalSteps: totalSteps,
                                             reduceMotion: accessibility.reduceMotion))
            .overlay(Color.white.opacity(ARC.Veil.opacity))
            .animation(accessibility.reduceMotion ? nil : .easeOut(duration: 0.4), value: step)
    }
}

extension View {
    func milkVeil(step: Int, totalSteps: Int) -> some View {
        modifier(MilkVeil(step: step, totalSteps: totalSteps))
    }

    /// Fill the available space and crop the overflow.
    ///
    /// `.scaledToFill()` alone does NOT do this: it scales the image relative to a frame it has
    /// not been given, so an unconstrained one lays out at its natural size and the photo appears
    /// as a small rectangle floating in the corner. The frame has to come first and the clip
    /// second — the other order crops before there is anything to crop.
    func fillAndClip() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .contentShape(Rectangle())
    }
}

/// A grid that reflows to one column at large Dynamic Type.
///
/// The handoff's preset grid is a fixed two-column `LazyVGrid`, and the README requires "grids
/// reflow to one column" at AX5. At AX5 a two-column preset card cannot fit its own name.
struct ReflowingGrid<Content: View>: View {
    var spacing: CGFloat = ARC.Space.gap
    @ViewBuilder var content: Content

    @Environment(\.dynamicTypeSize) private var typeSize

    /// The threshold is accessibility1 rather than AX5: by the time type is that large the second
    /// column is already truncating, and waiting until AX5 means four broken sizes in between.
    var columnCount: Int { typeSize >= .accessibility1 ? 1 : 2 }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing),
                                 count: columnCount),
                  spacing: spacing) {
            content
        }
    }
}
