import SwiftUI

// Result — the core view. Recommendation: the WIPE SLIDER, because the promise
// is geometric fidelity: the eye tracks one edge across the divider and sees it
// not move. Tap-to-flip and hold-to-peek ride along as secondary gestures.
// VoiceOver: the comparison is ONE adjustable element.
struct ResultView: View {
    @State private var wipe: CGFloat = 0.55
    @State private var peekingBefore = false
    var styleName = "Scandinavian"

    var body: some View {
        VStack(spacing: 0) {
            comparison
            GlassSheet {
                VStack(spacing: 14) {
                    variantStrip
                    HStack(spacing: 8) {
                        Button("Save") {}.font(.body.weight(.semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(Capsule().fill(DS.ink))
                        Button("Try again") {}.font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .buttonStyle(.glass)
                            .accessibilityHint("Regenerates with the same prompt and a new seed")
                        Menu { // Share · Regenerate with edits · Delete
                            Button("Share…") {}
                            Button("Regenerate with edits") {}
                            Button("Delete", role: .destructive) {}
                        } label: { Text("···").frame(width: 48).padding(.vertical, 13) }
                        .buttonStyle(.glass)
                    }
                }
            }
            .offset(y: -DS.rSheet + 8)
        }
        .background(DS.canvas)
    }

    private var comparison: some View {
        GeometryReader { geo in
            ZStack {
                BeforePlaceholder()
                AfterPlaceholder()
                    .mask(alignment: .trailing) {
                        Rectangle().frame(width: peekingBefore ? 0 : geo.size.width * (1 - wipe))
                    }
                divider(at: geo.size.width * wipe)
                labels
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                wipe = min(max(v.location.x / geo.size.width, 0.02), 0.98)
            })
            .onTapGesture { withAnimation(DS.morph) { wipe = wipe < 0.5 ? 0.98 : 0.02 } }
            .onLongPressGesture(minimumDuration: 0.25) { peekingBefore = true } onPressingChanged: { p in
                if !p { peekingBefore = false }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Before and after comparison, \(styleName)")
        .accessibilityValue("After revealed, \(Int((1 - wipe) * 100)) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: wipe = max(wipe - 0.1, 0.02)
            case .decrement: wipe = min(wipe + 0.1, 0.98)
            @unknown default: break
            }
        }
        .accessibilityHint("Swipe up or down to reveal more. Double-tap to flip.")
    }

    private func divider(at x: CGFloat) -> some View {
        ZStack {
            Rectangle().fill(.white).frame(width: 2.5)
                .shadow(color: .black.opacity(0.35), radius: 6)
            Image(systemName: "arrow.left.and.right")
                .font(.footnote.weight(.bold)).foregroundStyle(DS.ink)
                .frame(width: 44, height: 44) // 44pt hit target
                .glassEffect(in: .circle)
        }
        .position(x: x, y: 0).offset(y: 0)
        .frame(maxHeight: .infinity)
    }

    private var labels: some View {
        VStack {
            HStack {
                Text("Before").font(.caption.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 11).padding(.vertical, 4)
                    .background(Capsule().fill(.black.opacity(0.55)))
                Spacer()
                Text("After · \(styleName)").font(.caption.weight(.semibold)).foregroundStyle(DS.ink)
                    .padding(.horizontal, 11).padding(.vertical, 4)
                    .glassEffect(in: .capsule)
            }
            .padding(16)
            Spacer()
        }
    }

    private var variantStrip: some View {
        HStack(spacing: 10) {
            ForEach(0..<3) { i in
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: [0xE7E0D4, 0xC9A97E, 0xE9E2D4][i]))
                    .frame(width: 56, height: 42)
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(i == 0 ? DS.accent : Color.black.opacity(0.12),
                                      lineWidth: i == 0 ? 2.5 : 1))
                    .accessibilityLabel("Variation \(i + 1)")
            }
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                .foregroundStyle(.tertiary)
                .frame(width: 56, height: 42)
                .overlay(Image(systemName: "plus").foregroundStyle(.secondary))
                .accessibilityLabel("New variation")
            Spacer()
            Text("3 of 3 done").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct BeforePlaceholder: View {
    var body: some View {
        LinearGradient(colors: [Color(hex: 0xB3A288), Color(hex: 0x75604A)],
                       startPoint: .top, endPoint: .bottom)
    }
}
struct AfterPlaceholder: View {
    var body: some View {
        LinearGradient(colors: [Color(hex: 0xF0EBE2), Color(hex: 0xC4AC82)],
                       startPoint: .top, endPoint: .bottom)
    }
}
