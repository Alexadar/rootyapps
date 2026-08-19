import SwiftUI

struct SettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("The draw") {
                    if AppModel.reversalsFeatureEnabled {
                        Toggle("Allow reversed cards", isOn: $model.allowsReversals)
                            .accessibilityIdentifier("settings.reversals")
                    }
                    Toggle("Haptics", isOn: $model.hapticsEnabled)
                        .accessibilityIdentifier("settings.haptics")
                }
                Section("Audio") {
                    if AppModel.musicFeatureEnabled {
                        Toggle("Music", isOn: $model.musicEnabled)
                            .accessibilityIdentifier("settings.music")
                    }
                    Toggle("Sounds", isOn: $model.soundsEnabled)
                        .accessibilityIdentifier("settings.sounds")
                }
                Section {
                    // The toggle only where it can do something: on ineligible hardware the
                    // availability line below already tells the whole story.
                    if model.writer.availability == .available {
                        Toggle("Interpretations", isOn: $model.interpretationsEnabled)
                            .accessibilityIdentifier("settings.interpretations")
                    }
                    Text(availabilityLine)
                        .font(Tokens.body(14))
                        .foregroundStyle(Tokens.inkDim)
                        .accessibilityIdentifier("settings.availability")
                } header: {
                    Text("On-device writing")
                } footer: {
                    Text("Readings are written by Apple Intelligence on this device. Nothing leaves it. Reduce Motion is respected from the system setting.")
                }

                // The responsibility clause, once, where somebody reads it deliberately rather
                // than under every reading. The panel already carries the register at the moment
                // it matters ("…not a prediction"); repeating a legal-sounding sentence beneath
                // each draw reads as nagging and would say it in the place a reader is least
                // receptive to it.
                //
                // The wording follows the guidance that actually applies to this trade. UK
                // consumer law (Consumer Protection from Unfair Trading Regulations 2008, which
                // replaced the Fraudulent Mediums Act) does NOT require an "entertainment purposes
                // only" label — the government said so explicitly — and Apple's Guideline 1.1.6
                // says that phrase overcomes nothing anyway. What is recommended, and what is
                // actually defensible, is to disclaim CONTROL rather than to disclaim seriousness.
                Section {
                    Text(Self.responsibilityNote)
                        .font(Tokens.body(13))
                        .foregroundStyle(Tokens.inkDim)
                        .accessibilityIdentifier("settings.responsibility")
                } header: {
                    Text("About the readings")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("settings.done")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }

    /// Shared with the tests so the wording cannot quietly soften.
    static let responsibilityNote = L.loc("""
        This app shuffles a deck, deals it, and writes about the cards it dealt. It does not \
        predict the future and does not tell fortunes. The cards cannot tell you what to do, and \
        the decisions you take — or do not take — remain your own. Nothing here is medical, \
        legal, financial or psychological advice.
        """)

    private var availabilityLine: String {
        switch model.writer.availability {
        case .available: L.loc("Apple Intelligence is available.")
        case .deviceNotEligible: L.loc("This device can't run Apple Intelligence; draws work without the written reflection.")
        case .notEnabled: L.loc("Apple Intelligence is off. Enable it in Settings → Apple Intelligence & Siri.")
        case .modelNotReady: L.loc("The model is still downloading; drawing works meanwhile.")
        }
    }
}
