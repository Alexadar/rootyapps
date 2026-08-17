import SwiftUI
import TarotKit

/// The game menu — presence, not a form. The live deck glimmers behind it; the chrome is a
/// title and two pieces of glass.
struct MenuOverlay: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false
    @Namespace private var glassSpace

    var body: some View {
        VStack {
            #if os(iOS)
            HStack {
                Spacer()
                ARToggleButton()
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            #endif
            Spacer(minLength: 40)
            VStack(spacing: 10) {
                Text("Tarot")
                    .font(Tokens.title(64))
                    .foregroundStyle(Tokens.gold)
                    .shadow(color: Tokens.gold.opacity(0.35), radius: 18)
                Text(L.loc(model.selectedMethod.tagline))
                    .font(Tokens.body(19))
                    .foregroundStyle(Tokens.inkDim)
            }
            .accessibilityIdentifier("menu.title")

            #if DEBUG
            if let stats = model.frameStats {
                Text(stats)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Tokens.gold.opacity(0.8))
                    .padding(.top, 6)
            }
            if let status = model.fmProbeStatus {
                Text(status)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Tokens.inkDim)
                    .frame(maxWidth: 640)
                    .padding(8)
            }
            #endif

            Spacer()

            #if os(iOS)
            ARPlacementControls()
                .padding(.bottom, 10)
            #endif

            GlassEffectContainer(spacing: 18) {
                VStack(spacing: 14) {
                    @Bindable var model = model
                    TextField("Ask a question (optional)", text: $model.question, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(Tokens.body(17))
                        .foregroundStyle(Tokens.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(1...3)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .frame(maxWidth: 300)
                        .tarotGlassChip()
                        .accessibilityIdentifier("menu.question")

                    // The two creative choices of a draw, side by side: how to lay the
                    // cards (method) and whose names they carry (deck). Persisted; the
                    // table re-lays itself live as the method changes.
                    HStack(spacing: 10) {
                        Picker(selection: $model.selectedMethodID) {
                            ForEach(Spread.all) { method in
                                Text(L.loc(method.displayName)).tag(method.id)
                            }
                        } label: {
                            Text("Method")
                        }
                        .pickerStyle(.menu)
                        .tint(Tokens.ink)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)   // both chips take half the row
                        .tarotGlassChip()
                        .accessibilityIdentifier("menu.method")

                        Picker(selection: $model.selectedDeckID) {
                            ForEach(Deck.all) { deck in
                                Text(L.loc(deck.displayName)).tag(deck.id)
                            }
                        } label: {
                            Text("Deck")
                        }
                        .pickerStyle(.menu)
                        .tint(Tokens.ink)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .tarotGlassChip()
                        .accessibilityIdentifier("menu.deck")
                    }
                    .frame(maxWidth: 300)

                    Button {
                        model.startDraw()
                    } label: {
                        Text("Begin a Draw")
                            .font(Tokens.label(20))
                            .frame(maxWidth: 280)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Tokens.gold.opacity(0.8))
                    .accessibilityIdentifier("menu.start")

                    Button {
                        showSettings = true
                    } label: {
                        Text("Settings")
                            .font(Tokens.label(17))
                            .frame(maxWidth: 280)
                    }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("menu.settings")
                }
            }
            .padding(.bottom, 70)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showSettings) { SettingsSheet() }
    }
}
