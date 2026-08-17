import SwiftUI
import RecipeKit

/// The one dial (`1b`, `1i`).
///
/// A custom control rather than a `Slider`, for three reasons the system one cannot do:
///
/// 1. **Named detents.** The rail shows four ticks and the readout says "Subtle · 35", and VoiceOver
///    announces the *name*, never a bare number (`1j`).
/// 2. **Settling.** A drag that ends near a detent lands on it; one that ends between them stays put.
/// 3. **Two meanings.** Before a pass this is a request; after one it is a live blend, and the label
///    says which — "Strength" versus "Strength — live".
struct StrengthSlider: View {

    @Environment(\.colorScheme) private var scheme

    @Binding var strength: Strength
    /// After a pass the dial re-blends instantly; before one it is a request to the model.
    var isLive: Bool
    /// Set when the dial has been pushed above what was rendered, so the caption can say the pass
    /// has to run again rather than showing a picture that does not match the number.
    var needsRerun: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ST.Space.tight) {
            HStack {
                Text(isLive ? "Strength — live" : "Strength")
                    .stFont(.caption)
                    .foregroundStyle(ST.ink3(scheme))
                Spacer()
                Text(strength.displayName)
                    .stFont(.readout, tabularNumbers: true)
                    .foregroundStyle(ST.ink(scheme))
                    .contentTransition(.numericText())
                    .accessibilityHidden(true)   // spoken by the rail below, once
            }

            rail

            HStack(spacing: 0) {
                ForEach(Detent.allCases, id: \.self) { detent in
                    Text(detent.name)
                        .stFont(.footnote)
                        .foregroundStyle(strength.detent == detent ? ST.accent : ST.ink3(scheme))
                        .frame(maxWidth: .infinity,
                               alignment: alignment(for: detent))
                }
            }
            .accessibilityHidden(true)

            if let warning = strength.warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .stFont(.footnote)
                    .foregroundStyle(ST.ink2(scheme))
                    .transition(.opacity)
                    .accessibilityIdentifier("edit.strength.warning")
            }
            if needsRerun {
                Label("Above what was rendered — Enhance again to see it.",
                      systemImage: "arrow.clockwise")
                    .stFont(.footnote)
                    .foregroundStyle(ST.ink2(scheme))
                    .transition(.opacity)
                    .accessibilityIdentifier("edit.strength.rerun")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: strength)
        .animation(.easeInOut(duration: 0.2), value: needsRerun)
    }

    private var rail: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(ST.ink(scheme).opacity(0.10))
                    .frame(height: 6)

                Capsule()
                    .fill(ST.accent)
                    .frame(width: width * strength.fraction, height: 6)

                ForEach(Detent.allCases, id: \.self) { detent in
                    Circle()
                        .fill(ST.ink(scheme).opacity(0.22))
                        .frame(width: 4, height: 4)
                        .offset(x: width * (detent.rawValue / 100) - 2)
                }

                Circle()
                    .fill(.white)
                    .frame(width: 26, height: 26)
                    .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
                    .overlay(Circle().strokeBorder(ST.accent, lineWidth: 2))
                    .offset(x: width * strength.fraction - 13)
            }
            .frame(height: ST.minimumHitTarget)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        strength = Strength(Double(value.location.x / width) * 100)
                    }
                    .onEnded { _ in
                        // Settling happens on release, not during the drag: snapping under a moving
                        // finger feels like the control fighting back.
                        strength = strength.snapped()
                    }
            )
        }
        .frame(height: ST.minimumHitTarget)
        .accessibilityElement()
        .accessibilityIdentifier("edit.strength")
        .accessibilityLabel("Strength")
        // ⚠️ Detent names, not bare numbers.
        .accessibilityValue(strength.accessibilityValue)
        .accessibilityAdjustableAction { direction in
            let step: Double = 5
            switch direction {
            case .increment: strength = Strength(strength.value + step)
            case .decrement: strength = Strength(strength.value - step)
            @unknown default: break
            }
        }
    }

    /// The four labels sit under their ticks, so the outer two hug the ends of the rail rather than
    /// centring in a quarter that does not correspond to where the tick is.
    private func alignment(for detent: Detent) -> Alignment {
        switch detent {
        case .whisper: return .leading
        case .strong:  return .trailing
        default:       return .center
        }
    }
}
