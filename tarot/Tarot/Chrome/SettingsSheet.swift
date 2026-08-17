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

    private var availabilityLine: String {
        switch model.writer.availability {
        case .available: L.loc("Apple Intelligence is available.")
        case .deviceNotEligible: L.loc("This device can't run Apple Intelligence; draws work without the written reflection.")
        case .notEnabled: L.loc("Apple Intelligence is off. Enable it in Settings → Apple Intelligence & Siri.")
        case .modelNotReady: L.loc("The model is still downloading; drawing works meanwhile.")
        }
    }
}
