import SwiftUI
import FormatKit

/// The first-run gate — consent, downloading, interrupted, ready (bundle `4a`).
///
/// Shown once. There is no skip, because the app genuinely cannot make a wallpaper without the
/// model, and a skip button leading to a dead Create screen would be worse than an honest wall.
/// Once the model is installed this never appears again.
struct GateView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.wpAccessibility) private var accessibility

    var gate: ModelGate
    /// Called when the user leaves the gate with the model in place.
    var onReady: () -> Void
    /// "Look around meanwhile" — the compile is the one gate state that can be walked past.
    var onLookAround: () -> Void = {}
    /// Called by *Make your first wallpaper* with a prompt already chosen.
    var onSurpriseMe: () -> Void

    var body: some View {
        ZStack {
            AmbientBackground(recent: nil)
            content
                .frame(maxWidth: 520)
                .padding(.horizontal, WP.Space.margin)
        }
        .animation(WPMotion.morph(reduceMotion: accessibility.reduceMotion), value: gate.phase)
    }

    @ViewBuilder
    private var content: some View {
        switch gate.phase {
        case .checking:
            // Deliberately empty. A spinner here would flash at every user who already has the
            // model, for the one frame it takes to read the pack's status.
            Color.clear
        case .consent:
            consent
        case .downloading:
            downloading
        case .interrupted(_, _, let reason):
            interrupted(reason: reason)
        case .tuning(let part, let total):
            tuning(part: part, of: total)
        case .ready:
            ready
        case .failed(let reason):
            failed(reason: reason)
        }
    }

    // MARK: Consent

    private var consent: some View {
        VStack(alignment: .leading, spacing: WP.Space.section) {
            VStack(alignment: .leading, spacing: WP.Space.gap) {
                Text("Everything happens\non your \(Self.deviceNoun)")
                    .wpFont(.gateHeadline)
                    .foregroundStyle(WP.ink(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                Text("AISixteen makes wallpapers with a model that runs entirely on this device. One download, then it works forever — offline, private, no account.")
                    .wpFont(.body)
                    .foregroundStyle(WP.ink2(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: WP.Space.grid) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Image model").wpFont(.body, tabularNumbers: false).fontWeight(.semibold)
                    Spacer()
                    Text(ByteText.size(ModelGate.advertisedSize))
                        .wpFont(.secondary, tabularNumbers: true)
                        .foregroundStyle(WP.ink2(scheme))
                }
                .foregroundStyle(WP.ink(scheme))

                Rectangle().fill(WP.ink(scheme).opacity(0.10)).frame(height: 0.5)

                Toggle(isOn: Bindable(gate).wifiOnly) {
                    Text("Download over Wi‑Fi only")
                        .wpFont(.secondary)
                        .foregroundStyle(WP.ink(scheme).opacity(0.75))
                }
                .tint(Color(hex: 0x34C759))

                Text("Hosted by Apple, downloaded once. It never phones home — the app has no network access after this.")
                    .wpFont(.footnote)
                    .foregroundStyle(WP.ink3(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(WP.Space.margin - 2)
            .wpGlassCard()

            VStack(spacing: WP.Space.gap) {
                PrimaryCapsuleButton(title: "Download · \(ByteText.size(ModelGate.advertisedSize))") {
                    gate.beginDownload()
                }
                Text("You can keep using your \(Self.deviceNoun.lowercased()) — it continues in the background.")
                    .wpFont(.caption)
                    .foregroundStyle(WP.ink3(scheme))
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: Downloading

    private var downloading: some View {
        VStack(alignment: .leading, spacing: WP.Space.section) {
            headline("Getting the model", body: gate.remainingText)

            VStack(alignment: .leading, spacing: WP.Space.gap) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Image model").wpFont(.body).fontWeight(.semibold)
                    Spacer()
                    Text(gate.byteText)
                        .wpFont(.secondary, tabularNumbers: true)
                        .foregroundStyle(WP.ink2(scheme))
                }
                .foregroundStyle(WP.ink(scheme))

                ProgressBar(fraction: gate.fraction, desaturated: false)

                HStack {
                    Text(gate.rateText)
                        .wpFont(.caption, tabularNumbers: true)
                        .foregroundStyle(WP.ink3(scheme))
                    Spacer()
                    // Not "Pause". Background Assets has no app-callable pause, and a chip that
                    // pretended to have one would either lie or throw away the bytes already
                    // fetched. This does what the framework really supports: the user leaves, the
                    // system carries on, and the gate re-attaches to the live count on return.
                    Button("Continue in background") { onReady() }
                        .buttonStyle(.plain)
                        .wpFont(.caption)
                        .foregroundStyle(WP.ink(scheme))
                        .padding(.horizontal, WP.Space.grid)
                        .padding(.vertical, WP.Space.tight)
                        .background(WP.ink(scheme).opacity(0.08), in: Capsule())
                }
            }
            .padding(WP.Space.margin - 2)
            .wpGlassCard()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Downloading the image model")
        .accessibilityValue(gate.byteText)
    }

    // MARK: Interrupted

    private func interrupted(reason: String) -> some View {
        VStack(alignment: .leading, spacing: WP.Space.section) {
            headline("Getting the model", body: "Nothing is lost — it picks up exactly where it stopped.")

            VStack(alignment: .leading, spacing: WP.Space.gap) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Image model").wpFont(.body).fontWeight(.semibold)
                    Spacer()
                    Text(gate.byteText)
                        .wpFont(.secondary, tabularNumbers: true)
                        .foregroundStyle(WP.ink2(scheme))
                }
                .foregroundStyle(WP.ink(scheme))

                // The bar desaturates to 25% ink — but the state is carried by the sentence below
                // it, never by the colour alone.
                ProgressBar(fraction: gate.fraction, desaturated: true)

                Text(reason)
                    .wpFont(.caption)
                    .foregroundStyle(WP.ink2(scheme))

                HStack(spacing: WP.Space.gap) {
                    Button("Use cellular this once") { gate.useCellularOnce() }
                        .buttonStyle(.glassProminent)
                        .tint(WP.accent)
                    Button("Keep waiting") { gate.keepWaiting() }
                        .buttonStyle(.glass)
                }
                .wpFont(.control)
                .padding(.top, WP.Space.hair)
            }
            .padding(WP.Space.margin - 2)
            .wpGlassCard()
        }
    }

    // MARK: Ready

    // MARK: Tuning (6a) — the one-time Neural Engine compile

    /// The wait nobody designed for until it was the only wait left.
    ///
    /// Embedding the model deleted the download gate, and that gate had also been carrying this:
    /// minutes of silence on first launch while `ANECompilerService` compiles six graphs out of
    /// process. Once per install, again after an OS update, never otherwise.
    ///
    /// **It does not block.** "Look around meanwhile" opens the app; the Gallery works fully and the
    /// compile continues behind it. A blocking screen would be easier to build and would be lying
    /// about the constraint — nothing here needs the user to wait, it just needs time.
    private func tuning(part: Int, of total: Int) -> some View {
        VStack(alignment: .leading, spacing: WP.Space.section) {
            headline("Tuning for\nthis \(Self.deviceNoun)",
                     body: "The model is being compiled for this \(Self.deviceNoun.lowercased())'s "
                         + "Neural Engine. It happens once, takes a few minutes, and every launch "
                         + "after this is instant.")

            TuningChecklist(state: gate.checklist)

            VStack(alignment: .leading, spacing: WP.Space.gap) {
                PrimaryCapsuleButton(title: "Look around meanwhile") {
                    gate.lookAround()
                    onLookAround()
                }
                Text("It keeps working while you browse. Create unlocks when it's done.")
                    .wpFont(.caption)
                    .foregroundStyle(WP.ink3(scheme))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tuning for this \(Self.deviceNoun), \(part) of \(total) parts")
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: WP.Space.section) {
            VStack(alignment: .leading, spacing: WP.Space.gap) {
                Label {
                    Text("Ready").wpFont(.gateHeadline)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(WP.success(scheme))
                }
                .foregroundStyle(WP.ink(scheme))

                Text("The model lives on your \(Self.deviceNoun.lowercased()) now. You won't see this screen again.")
                    .wpFont(.body)
                    .foregroundStyle(WP.ink2(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: WP.Space.gap) {
                PrimaryCapsuleButton(title: "Make your first wallpaper", action: onReady)
                Button {
                    onSurpriseMe()
                } label: {
                    Label("Surprise me", systemImage: "sparkles")
                        .wpFont(.control)
                }
                .buttonStyle(.glass)
            }
        }
    }

    // MARK: Failed

    private func failed(reason: String) -> some View {
        VStack(alignment: .leading, spacing: WP.Space.gap) {
            Text("That didn't come through")
                .wpFont(.cardHeading)
                .foregroundStyle(WP.ink(scheme))
            Text(reason)
                .wpFont(.body)
                .foregroundStyle(WP.ink2(scheme))
                .fixedSize(horizontal: false, vertical: true)
            Text("Nothing was lost — it will pick up where it stopped.")
                .wpFont(.caption)
                .foregroundStyle(WP.ink3(scheme))
            Button("Try again") { gate.retry() }
                .buttonStyle(.glassProminent)
                .tint(WP.accent)
                .wpFont(.control)
                .padding(.top, WP.Space.tight)
        }
        .padding(WP.Space.margin)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wpGlassCard(radius: WP.Radius.frame)
    }

    // MARK: -

    private func headline(_ title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: WP.Space.gap) {
            Text(title)
                .wpFont(.gateHeadline)
                .foregroundStyle(WP.ink(scheme))
            Text(body)
                .wpFont(.body)
                .foregroundStyle(WP.ink2(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The copy names the device. Saying "on your iPhone" on a Mac is the kind of small wrongness
    /// that makes a privacy promise read as boilerplate.
    private static var deviceNoun: String {
        #if os(macOS)
        return "Mac"
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }
}

/// The 10 pt download bar. Desaturates to 25 % ink when the transfer is interrupted.
private struct ProgressBar: View {
    @Environment(\.colorScheme) private var scheme
    var fraction: Double
    var desaturated: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(WP.ink(scheme).opacity(0.08))
                Capsule()
                    .fill(desaturated ? WP.ink(scheme).opacity(0.25) : WP.accent)
                    .frame(width: max(0, min(1, fraction)) * proxy.size.width)
                    .animation(WPMotion.progressFill, value: fraction)
            }
        }
        .frame(height: 10)
    }
}

/// The 56 pt tinted capsule — one per screen, never two.
struct PrimaryCapsuleButton: View {
    @Environment(\.colorScheme) private var scheme
    var title: String
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .wpFont(.button)
                .foregroundStyle(GlassLabel.color(on: enabled ? .tinted : .regular,
                                                  scheme: scheme,
                                                  enabled: enabled))
                .frame(maxWidth: .infinity)
                .frame(height: WP.primaryCapsuleHeight)
        }
        .buttonStyle(.plain)
        .wpGlassCapsule(enabled ? .tinted : .regular)
        .disabled(!enabled)
        .accessibilityAddTraits(.isButton)
    }
}
