import SwiftUI
import PromptKit

/// The advanced controls, behind one disclosure.
///
/// Everything here has a working default, so a user who never opens it is not missing anything. It
/// is a sheet rather than a screen: the app has two screens and this is not a third.
struct AdvancedSheet: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    var settings: AdvancedSettings

    /// The list now lives in `Attribution`, beside the licence line it discharges. Kept as an alias
    /// rather than deleted: `AttributionChecks` asserts against this name, and that test passing
    /// unchanged is the proof the extraction dropped nothing on the way out.
    static let credits: [String] = Attribution.credits

    var body: some View {
        NavigationStack {
            AdvancedSettingsBody(settings: settings)
            .background(AmbientBackground(recent: nil))
            .navigationTitle("Advanced")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// The controls themselves, without the sheet chrome.
///
/// Split out so the About sheet can push the same settings as a navigation destination rather than
/// presenting a second sheet on top of the first — which SwiftUI handles poorly and which reads,
/// correctly, as the app losing its place.
struct AdvancedSettingsBody: View {
    @Environment(\.colorScheme) private var scheme

    var settings: AdvancedSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WP.Space.section) {
                negative
                stages
                acknowledgements
            }
            .padding(WP.Space.margin)
        }
    }

    // MARK: Acknowledgements

    /// Credit for the models the pictures are made with.
    ///
    /// **A licence term, not a courtesy.** The diffusion checkpoint is distributed under CivitAI
    /// terms with `allowNoCredit: false`, which obliges attribution wherever the weights are
    /// redistributed — and they are redistributed, in this app's bundle. Removing this section
    /// breaks the licence the app ships under.
    ///
    /// The others are listed because their terms deserve it even where they do not demand it, and
    /// because one honest list is easier to keep true than a list with silent omissions in it. The
    /// authoritative record travels with the weights, in `LICENCE.txt` beside the converted model.
    private var acknowledgements: some View {
        VStack(alignment: .leading, spacing: WP.Space.tight) {
            Text("Acknowledgements")
                .wpFont(.cardHeading)
                .foregroundStyle(WP.ink(scheme))
            Text("Pictures are made on this device by:")
                .wpFont(.caption)
                .foregroundStyle(WP.ink3(scheme))
            ForEach(Attribution.credits, id: \.self) { line in
                Text(line)
                    .wpFont(.caption)
                    .foregroundStyle(WP.ink2(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WP.Space.margin)
        .wpGlassCard()
        .accessibilityElement(children: .contain)
    }

    /// Kept as data so a test can assert the required credit is present. An attribution that can be
    /// deleted by a refactor without anything failing is an attribution that will be.


    // MARK: Negative prompt

    private var negative: some View {
        VStack(alignment: .leading, spacing: WP.Space.gap) {
            header("What to avoid", detail: "The model is told to steer away from these.")

            ZStack(alignment: .topLeading) {
                if settings.negativePrompt.isEmpty {
                    Text("Nothing — anything goes")
                        .wpFont(.secondary)
                        .foregroundStyle(WP.ink3(scheme))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
                TextEditor(text: Bindable(settings).negativePrompt)
                    .wpFont(.secondary)
                    .foregroundStyle(WP.ink(scheme))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .tint(WP.accent)
            }
            .frame(height: 132)
            .wpGlassCard(radius: WP.Radius.plate)

            // The limit is stated because exceeding it fails silently — CLIP drops the tail and the
            // picture looks as though the whole list was applied.
            HStack {
                Text(settings.negativeBudgetText)
                    .wpFont(.caption, tabularNumbers: true)
                    .foregroundStyle(settings.negativeIsWithinLimit
                                     ? WP.ink3(scheme) : WP.destructive(scheme))
                Spacer()
                Button("Wallpaper") { settings.resetNegativeToDefault() }
                    .buttonStyle(.plain)
                    .wpFont(.caption)
                    .foregroundStyle(WP.accent)
                Button("People") { settings.useFigurativeNegative() }
                    .buttonStyle(.plain)
                    .wpFont(.caption)
                    .foregroundStyle(WP.accent)
            }
        }
    }

    // MARK: Per-stage controls

    private var stages: some View {
        VStack(alignment: .leading, spacing: WP.Space.margin) {
            header("Stages", detail: "Each stage costs time. The defaults are what the app was tuned against.")

            stepper("Generate", value: Bindable(settings).generationSteps,
                    range: AdvancedSettings.generationStepRange,
                    note: "Diffusion steps. Above about 30 the picture stops changing.")

            Toggle(isOn: Bindable(settings).upscaleEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Upscale").wpFont(.body).foregroundStyle(WP.ink(scheme))
                    Text("Enlarges 4× before the wallpaper is fitted to your screen.")
                        .wpFont(.caption).foregroundStyle(WP.ink3(scheme))
                }
            }
            .tint(WP.accent)

            stepper("Enhance", value: Bindable(settings).refineSteps,
                    range: AdvancedSettings.refineStepRange,
                    note: "Steps per tile. At this strength only about a third of them run.")

            VStack(alignment: .leading, spacing: WP.Space.tight) {
                HStack {
                    Text("Enhance strength").wpFont(.body).foregroundStyle(WP.ink(scheme))
                    Spacer()
                    Text(String(format: "%.2f", settings.refineStrength))
                        .wpFont(.caption, tabularNumbers: true)
                        .foregroundStyle(WP.ink2(scheme))
                }
                Slider(value: Bindable(settings).refineStrength, in: 0.15...0.6, step: 0.05)
                    .tint(WP.accent)
                Text("How far each tile may depart from the picture. Higher invents detail that neighbouring tiles then disagree about.")
                    .wpFont(.caption).foregroundStyle(WP.ink3(scheme))
            }
        }
        .padding(WP.Space.margin)
        .wpGlassCard()
    }

    private func stepper(_ title: String, value: Binding<Int>,
                         range: ClosedRange<Int>, note: String) -> some View {
        VStack(alignment: .leading, spacing: WP.Space.tight) {
            Stepper(value: value, in: range) {
                HStack {
                    Text(title).wpFont(.body).foregroundStyle(WP.ink(scheme))
                    Spacer()
                    Text("\(value.wrappedValue)")
                        .wpFont(.body, tabularNumbers: true)
                        .foregroundStyle(WP.ink2(scheme))
                }
            }
            Text(note).wpFont(.caption).foregroundStyle(WP.ink3(scheme))
        }
    }

    private func header(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: WP.Space.hair) {
            Text(title).wpFont(.cardHeading).foregroundStyle(WP.ink(scheme))
            Text(detail).wpFont(.caption).foregroundStyle(WP.ink2(scheme))
        }
    }
}
