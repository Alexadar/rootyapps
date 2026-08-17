import SwiftUI

/// What the app shows while the scene is arriving.
///
/// RealityKit uploads a material's textures on the frame that material is first drawn, so the
/// opening frames show the table, the candles, the ball and the deck popping in one after
/// another. It is barely perceptible in the hand and unmissable on video — which is where it
/// matters most, because a store preview opens on exactly those frames.
///
/// So the app draws its own opening instead: the card back it already generates for this skin,
/// the wordmark, on the ground colour the table sits on. Not a spinner and deliberately no
/// progress: it is up for about a second, and a progress bar would make a fast launch look slow.
///
/// The layout deliberately MIRRORS `MenuOverlay` — same leading spacer, same 64pt gold title in
/// the same place — so the dissolve resolves into the menu instead of crossing two different
/// screens. The first version centred its own title and the handover showed two "Tarot"s sliding
/// past each other, which reads as a glitch rather than as a curtain.
struct LaunchCurtain: View {
    /// The back of a card in the CURRENT skin — generated art, not a bundled asset, so a skin
    /// the reader chose is the one that greets them.
    let back: CGImage

    var body: some View {
        ZStack {
            Tokens.background.ignoresSafeArea()
            // A pool of warm light behind the card, echoing the lamp over the table that the
            // first real frame will show.
            RadialGradient(colors: [Tokens.gold.opacity(0.13), .clear],
                           center: .init(x: 0.5, y: 0.34), startRadius: 2, endRadius: 460)
                .ignoresSafeArea()

            VStack {
                Spacer(minLength: 40)
                VStack(spacing: 10) {
                    Text("Tarot")
                        .font(Tokens.title(64))
                        .foregroundStyle(Tokens.gold)
                        .shadow(color: Tokens.gold.opacity(0.35), radius: 18)
                    // Holds the tagline's line box so the title sits at the menu's exact
                    // height. The words themselves belong to the menu, and fade in with it.
                    Text(" ")
                        .font(Tokens.body(19))
                }
                Spacer(minLength: 24)
                Image(decorative: back, scale: 1, orientation: .up)
                    .resizable()
                    .aspectRatio(CGFloat(back.width) / CGFloat(back.height), contentMode: .fit)
                    .frame(maxWidth: 108)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .shadow(color: .black.opacity(0.6), radius: 20, y: 8)
                    .shadow(color: Tokens.gold.opacity(0.20), radius: 26)
                Spacer(minLength: 40)
                Spacer()
            }
        }
    }
}
