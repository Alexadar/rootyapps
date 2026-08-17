import SwiftUI
import CardMotionKit
import TarotKit

/// The judged screen keeps its chrome nearly invisible: a hint chip and a way out. The cards
/// do the talking.
struct DrawOverlay: View {
    @Environment(AppModel.self) private var model

    private var hint: String {
        guard let world = model.world else { return "" }
        if model.arMode, !model.arPlaced {
            return "Aim at your table, then tap Place"
        }
        let landed = (world.phase .== MotionWorld.Phase.landed).setLanes(world: 0).count
        return L.loc(AppModel.drawHintKey(landed: landed, slotCount: model.config.slotCount))
    }

    /// The active draw's identity — read from the READING (the truth of this draw), not
    /// the pickers, which could in principle drift.
    private var activeMethod: Spread { Spread.method(id: model.reading?.spreadID ?? model.selectedMethodID) }
    private var activeDeck: Deck { Deck.deck(id: model.reading?.deckID ?? model.selectedDeckID) }

    var body: some View {
        VStack {
            HStack(alignment: .top) {
                Button {
                    model.backToMenu()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(Tokens.label(16))
                        .padding(10)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("draw.back")

                // What this draw IS. One chip on one line, beside the back button: a
                // stacked column of them ate the top of the screen and crowded the hint
                // (owner: "clumsy, some overflows").
                VStack(alignment: .leading, spacing: 5) {
                    badge("\(L.loc(activeMethod.displayName)) · \(L.loc(activeDeck.displayName))",
                          id: "draw.badge.method")
                    if !model.interpretationsEnabled {
                        badge(L.loc("Interpretations are off."), id: "draw.badge.interpretations")
                    }
                    #if DEBUG
                    if let stats = model.frameStats {
                        badge(stats, id: "draw.badge.frame")
                    }
                    #endif
                }
                .padding(.leading, 6)
                .padding(.top, 6)

                Spacer()
                #if os(iOS)
                ARToggleButton()
                #endif
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)

            Text(hint)
                .font(Tokens.body(16))
                .foregroundStyle(Tokens.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .tarotGlassChip()
                .padding(.top, 10)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)          // centred on the SCREEN, not on what is left of it
                .accessibilityIdentifier("draw.hint")
                .animation(.easeInOut(duration: 0.25), value: hint)

            Spacer()

            #if os(iOS)
            ARPlacementControls()
                .padding(.bottom, 24)
            #endif
        }
    }

    private func badge(_ text: String, id: String) -> some View {
        Text(text)
            .font(Tokens.label(12))
            .foregroundStyle(Tokens.inkDim)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .tarotGlassChip()
            .accessibilityIdentifier(id)
    }
}
