import SwiftUI
import DimensionKit

/// The tape measure graphic — *"No need to guess where to place your mark."*
///
/// **Takes no arithmetic decisions of its own.** Where the cursor sits comes from
/// `Tape.position(of:)`; a tapped or dragged value comes from `Tape.value(atPosition:)` and
/// `Tape.scrubbing(…)`. This view only decides geometry — how tall a tick is and where a label goes.
///
/// - **Defect ②** — a graphic that showed the wrong result. Position is unit tested before any
///   pixel is drawn, and so is its inverse.
/// - **Defect ④** — the blade is labelled in **feet and inches**, never a running inch count, and
///   when `Tape.smallest(for:)` returns `nil` nothing is drawn. There is no fallback that stretches
///   a tape past reality.
struct TapeView: View {
    let value: FeetInch
    var denominator: Int64 = 16

    /// Supply this and the blade becomes an input — **tap to place the mark, drag to fine-tune**.
    /// Two of the incumbent's own users asked for exactly this, fourteen years apart:
    /// *"we can just move the red hairline and indicate the measurement!"* (5★ 2012-09-11) and
    /// *"'scroll' this ruler left to right … If this number could then be selected in some way for
    /// use in calculations, it would save the user some steps."* (4★ 2016-12-04).
    var onScrub: ((FeetInch) -> Void)? = nil

    fileprivate static let bladeHeight: CGFloat = 76
    private static let dragSlop: CGFloat = 3

    /// How much blade one full-width drag covers, chosen by how far the finger has drifted off the
    /// tape. A single fixed window is the wrong trade: fine enough to pick a sixteenth is far too
    /// fine to travel twenty feet.
    ///
    /// Inverted from a media scrubber on purpose — **on the blade is precise, away is coarse** —
    /// because on a tape the precision lives on the blade, where the graduations are. Keep your
    /// finger on it to place a sixteenth; drag off it to cover eight feet in one sweep.
    @State private var scale: Tape.ScrubScale = .precise
    private var windowSpan: FeetInch { scale.span }

    @State private var anchor: FeetInch?
    @State private var lastEmitted: FeetInch?
    /// The blade in force for the whole gesture. Without this, crossing 12'0" swaps the 12 ft
    /// blade for the 16 ft one *mid-drag*: the scale changes under your finger and `scrubbing`
    /// re-clamps against a different length, which reads as the tape refusing to scroll past the
    /// point you were on.
    @State private var anchorTape: Tape?

    private var tape: Tape? { anchorTape ?? Tape.smallest(for: value) }
    private var isScrubbing: Bool { anchor != nil }
    private var interactive: Bool { onScrub != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: SP.s2) {
            if let tape, let position = tape.position(of: value) {
                // ONE view, always. An `if` here would swap view identity the instant a drag set
                // `anchor`, which cancels the in-flight gesture — it would move a single detent
                // and then die. Only what the Canvas draws changes.
                bladeSurface(tape: tape, position: position, zoomed: isScrubbing)
                    .gesture(interactive ? gesture(for: tape) : nil)
                    .animation(nil, value: isScrubbing)
                footer(tape: tape)
            } else {
                noTape
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Tape measure"))
        .accessibilityValue(Text(value.formatted(toDenominator: denominator)))
        .accessibilityHint(Text(interactive ? "Tap the tape to place a mark, or drag to fine-tune." : ""))
        .accessibilityAdjustableAction { direction in
            guard interactive, let tape else { return }
            let step = FeetInch(inches: Rational(1, denominator))
            let next = direction == .increment ? value + step : value - step
            if !next.isNegative, !(tape.length < next) { onScrub?(next) }
        }
    }

    // MARK: - Gesture
    //
    // One `DragGesture` with `minimumDistance: 0` handles BOTH a tap and a drag, which avoids the
    // tap-vs-drag arbitration that a separate SpatialTapGesture would need. Under the slop
    // threshold nothing is emitted; past it the blade zooms and starts scrubbing. On release with
    // no movement it is a tap, and the mark jumps to that point on the full blade.

    private func gesture(for tape: Tape) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { g in
                guard abs(g.translation.width) >= Self.dragSlop || anchor != nil else { return }
                if anchor == nil {
                    anchor = value
                    baselineX = g.translation.width
                    // Pin the blade for the whole gesture: without this, crossing 12'0" swaps the
                    // blade mid-drag, the scale changes under the finger and `scrubbing` re-clamps
                    // against a different length.
                    anchorTape = Tape.smallest(for: value) ?? Tape.longest
                }
                // Vertical drift picks the scale, re-evaluated every frame, so one gesture can
                // start on the blade in sixteenths, slide off to travel eight feet, and come back
                // to land the mark — without ever lifting a finger.
                let next = Tape.ScrubScale.forVerticalDrift(g.translation.height)
                if next != scale {
                    // Re-anchor at the switch. The accumulated translation was measured against
                    // the OLD span, so carrying it into the new one would teleport the mark.
                    anchor = value
                    baselineX = g.translation.width
                    scale = next
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.82)) {
                        animSpanIn = next.span.inchesValue
                    }
                    shift()
                }
                let blade = anchorTape ?? tape
                let dx = g.translation.width - baselineX
                let fraction = dx / max(measuredWidth, 1)
                let moved = blade.scrubbing(from: anchor ?? value, byFraction: fraction,
                                            windowSpan: next.span, denominator: denominator)
                emitIfChanged(moved)
            }
            .onEnded { g in
                if anchor == nil {
                    // A tap: rough placement anywhere on the blade, then drag to refine.
                    let p = measuredWidth > 0 ? g.location.x / measuredWidth : 0
                    emitIfChanged(tape.value(atPosition: p, denominator: denominator))
                }
                anchor = nil
                anchorTape = nil
                lastEmitted = nil
                baselineX = 0
                scale = .precise
                animSpanIn = Tape.ScrubScale.precise.span.inchesValue
            }
    }

    @State private var measuredWidth: CGFloat = 1
    @State private var baselineX: CGFloat = 0
    /// The span actually being drawn. Follows `scale.span`, but through a spring, so a tier change
    /// racks the blade out instead of teleporting it.
    @State private var animSpanIn: Double = Tape.ScrubScale.precise.span.inchesValue

    private func emitIfChanged(_ next: FeetInch) {
        guard next != lastEmitted else { return }
        lastEmitted = next
        tick()
        onScrub?(next)
    }

    /// A firmer knock when the scrub scale changes tier — distinguishable from a detent.
    private func shift() {
#if os(iOS)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.9)
#endif
    }

    /// One haptic per detent crossed — the same feel as the crown on the watch.
    private func tick() {
#if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
#endif
    }

    // MARK: - The blade

    private func bladeSurface(tape: Tape, position: Double, zoomed: Bool) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: [SP.tapeBody, SP.tapeBodyLo],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(SP.tapeEdge, lineWidth: 1)
                    )

                // `spanIn` is the ONE animatable quantity here. Changing scale tier used to snap
                // the graduations from 2" to 8 ft in a single frame, which reads as a glitch
                // rather than a zoom; interpolating the span makes the blade visibly rack out.
                BladeCanvas(spanIn: animSpanIn,
                            centreIn: value.inchesValue,
                            bladeIn: tape.length.inchesValue,
                            lengthFeet: tape.lengthFeet,
                            zoomed: zoomed)
                    .frame(height: Self.bladeHeight)

                // Zoomed, the cursor is pinned to the centre and the blade moves beneath it.
                let cx = zoomed ? w / 2 : w * position
                Path { p in
                    p.move(to: CGPoint(x: cx, y: 0))
                    p.addLine(to: CGPoint(x: cx, y: Self.bladeHeight))
                }
                .stroke(SP.tapeCursor, lineWidth: 2.5)
                Circle()
                    .fill(SP.tapeCursor)
                    .frame(width: 9, height: 9)
                    .position(x: cx, y: 4.5)

                // The hook, at true zero — only meaningful on the full blade.
                // Driven by opacity, never by an `if`: inserting and removing a view mid-drag makes
                // SwiftUI cross-fade it, which shows up as a ghost sliding under your finger.
                RoundedRectangle(cornerRadius: 2)
                    .fill(SP.tapeHook)
                    .frame(width: 5, height: Self.bladeHeight)
                    .opacity(zoomed ? 0 : 1)
            }
            .contentShape(.rect)                       // the whole blade is the hit target
            .onAppear { measuredWidth = w }
            .onChange(of: w) { _, new in measuredWidth = new }
        }
        .frame(height: Self.bladeHeight)
        .accessibilityIdentifier(zoomed ? "tape.scrub" : "tape.blade.surface")
    }

    // MARK: - Footer

    /// Fixed structure — one leading `Text`, one symbol, one trailing `Text` — with only their
    /// *content* and opacity changing. An `if/else` here swaps view identity on every drag update,
    /// and SwiftUI cross-fades the outgoing SF Symbol, which reads as a ghost overlaying the tape.
    private func footer(tape: Tape) -> some View {
        HStack(spacing: SP.s1) {
            Text(isScrubbing
                 ? value.formatted(toDenominator: denominator)
                 : "\(String(tape.lengthFeet)) ft tape")
                .accessibilityIdentifier("tape.blade")
            Spacer(minLength: 0)
            Image(systemName: "hand.tap")
                .opacity(interactive && !isScrubbing ? 1 : 0)
                .accessibilityHidden(true)
            Text(trailing(tape))
        }
        .font(SPType.footnote)
        .foregroundStyle(isScrubbing ? SP.accent : SP.textTertiary)
        .animation(nil, value: isScrubbing)     // no cross-fade while a finger is down
    }

    private func trailing(_ tape: Tape) -> String {
        // While dragging, the finger hides the blade — so the ACTIVE SCALE has to be stated, and
        // how to change it. This is the same reason iOS players print "Half-Speed Scrubbing".
        if isScrubbing { return "\(scale.name) · slide up/down" }
        if interactive { return "tap or drag" }
        return tape.length.formatted(toDenominator: 1)
    }

    // MARK: - The refusal

    /// `Tape.smallest(for:)` returned nil. The number stands alone; nothing is drawn.
    private var noTape: some View {
        HStack(spacing: SP.s3) {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(SP.textTertiary, lineWidth: 1.5)
                .frame(width: 26, height: 14)
            Text(value.isNegative
                 ? "A tape has no negative side."
                 : "Longer than any real tape — no blade to draw.")
                .font(SPType.label)
                .foregroundStyle(SP.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, SP.s3)
        .accessibilityIdentifier("tape.none")
    }
}

// MARK: - The blade canvas

/// The graduations, as an `Animatable` view.
///
/// Conforming to `Animatable` with `spanIn` as `animatableData` is what lets a scale change be a
/// *zoom*: SwiftUI re-invokes `body` with interpolated spans for the duration of the spring, so the
/// ticks visibly rack in or out. A plain `@State` Double would not animate — `Canvas` would simply
/// redraw once at the new value.
///
/// Only the span animates. The cursor never does: the mark must track the finger exactly.
private struct BladeCanvas: View, Animatable {
    var spanIn: Double
    let centreIn: Double
    let bladeIn: Double
    let lengthFeet: Int
    let zoomed: Bool

    var animatableData: Double {
        get { spanIn }
        set { spanIn = newValue }
    }

    var body: some View {
        Canvas { ctx, size in
            if zoomed { drawWindow(ctx, size) } else { drawFullBlade(ctx, size) }
        }
    }

        /// Full blade: 1/2 ft short, 1 ft tall, feet labelled and thinned so they never collide.
        private func drawFullBlade(_ ctx: GraphicsContext, _ size: CGSize) {
            let inches = bladeIn
            let step = lengthFeet > 16 ? 5 : (lengthFeet > 12 ? 2 : 1)
            for half in 0...(lengthFeet * 2) {
                let x = size.width * (Double(half) * 6 / inches)
                let isFoot = half % 2 == 0
                var p = Path()
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: isFoot ? 20 : 11))
                ctx.stroke(p, with: .color(SP.tapeMark.opacity(isFoot ? 0.75 : 0.35)),
                           lineWidth: isFoot ? 1.5 : 1)
                let foot = half / 2
                // DROP a label that will not fit, never clamp it back inside. Clamping put the
                // final foot mark on top of its neighbour: on a 12 ft blade "11'" and "12'"
                // rendered as an unreadable "1112", and it reached a store screenshot before
                // anyone looked at the frame.
                if isFoot, foot % step == 0, size.width - x > 30 {
                    let label = Text(foot == 0 ? "0" : "\(foot)'")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(SP.tapeMark.opacity(0.85))
                    ctx.draw(label, at: CGPoint(x: x + 4, y: 30), anchor: .topLeading)
                }
            }
        }

        /// The graduation the window steps by, in sixteenths, chosen so ticks never crowd.
        ///
        /// The scale is variable now, so a fixed sixteenth step is wrong at both ends: across an 8 ft
        /// window it is 1,536 ticks of grey mush (and 1,536 `Path`s a frame), while across a 2" window
        /// sixteenths are exactly right. Pick the finest step that still leaves ~5 pt between ticks.
        private func gradStep(spanIn: Double, width: CGFloat) -> Int {
            let candidates = [1, 2, 4, 8, 16, 32, 96, 192, 576]   // 1/16" … 4 ft
            let ptPerSixteenth = Double(width) / (spanIn * 16)
            return candidates.first { Double($0) * ptPerSixteenth >= 5 } ?? candidates.last!
        }

        /// Zoomed window. Whole inches tall and labelled, coarser divisions medium, the finest step
        /// short. Geometry only — no measurement arithmetic happens here.
        private func drawWindow(_ ctx: GraphicsContext, _ size: CGSize) {
            // `spanIn` is the interpolated value SwiftUI hands us mid-animation.
            let lo = centreIn - spanIn / 2
            let step = gradStep(spanIn: spanIn, width: size.width)
            // Label only where there is room for the glyphs, on a foot-friendly multiple.
            let labelEvery = max(step, [16, 48, 96, 192, 576].first {
                Double($0) * (Double(size.width) / (spanIn * 16)) >= 26
            } ?? 576)

            var n = (Int((lo * 16).rounded(.up)) / step) * step
            let last = Int(((lo + spanIn) * 16).rounded(.down))
            while n <= last {
                defer { n += step }
                let inch = Double(n) / 16
                guard inch >= 0, inch <= bladeIn else { continue }
                let x = size.width * ((inch - lo) / spanIn)
                let isFootMark = n % 192 == 0
                let isInch = n % 16 == 0
                var p = Path()
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: isFootMark ? 30 : (isInch ? 26 : (n % (step * 4) == 0 ? 15 : 8))))
                ctx.stroke(p, with: .color(SP.tapeMark.opacity(isInch ? 0.8 : 0.4)),
                           lineWidth: isFootMark ? 2 : (isInch ? 1.5 : 1))

                if n % labelEvery == 0 {
                    // Label like a real blade: the foot mark carries the foot ("8'"), every other inch
                    // carries just its inch-within-foot (1…11). Printing the full "8' 4\"" at every
                    // inch overflowed into the next graduation — a 12" window gives each inch about
                    // 29 pt and "8' 4\"" needs more. Defect ④ still holds: no running count in the 200s.
                    let totalInches = n / 16
                    let feet = totalInches / 12
                    let inchInFoot = totalInches % 12
                    let label = Text(inchInFoot == 0 ? "\(feet)'" : "\(inchInFoot)")
                        .font(.system(size: inchInFoot == 0 ? 11 : 10, design: .monospaced)
                            .weight(inchInFoot == 0 ? .semibold : .regular))
                        .foregroundStyle(SP.tapeMark.opacity(inchInFoot == 0 ? 0.9 : 0.6))
                    ctx.draw(label, at: CGPoint(x: x + 3, y: 33), anchor: .topLeading)
                }
            }
        }
}

#Preview("On the blade") {
    VStack(spacing: SP.s5) {
        TapeView(value: FeetInch(feet: 8, inches: 10, num: 1, den: 4))
        TapeView(value: FeetInch(feet: 22))
        TapeView(value: FeetInch(feet: 40))          // no real tape — draws nothing
    }
    .padding()
    .background(SP.background)
}

#Preview("Interactive") {
    struct Demo: View {
        @State private var v = FeetInch(feet: 4, inches: 3, num: 1, den: 2)
        var body: some View {
            VStack(alignment: .leading, spacing: SP.s4) {
                Text(v.formatted(toDenominator: 16)).font(SPType.readout)
                TapeView(value: v, onScrub: { v = $0 })
            }
            .padding()
            .background(SP.background)
        }
    }
    return Demo()
}

#Preview("Dark") {
    VStack(spacing: SP.s5) {
        TapeView(value: FeetInch(feet: 8, inches: 10, num: 1, den: 4))
        TapeView(value: FeetInch(feet: 22))
    }
    .padding()
    .background(SP.background)
    .preferredColorScheme(.dark)
}
