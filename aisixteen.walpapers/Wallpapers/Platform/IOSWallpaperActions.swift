#if os(iOS)
import SwiftUI
import Photos
import LibraryKit
import GenerationKit

/// iOS and iPadOS: save to Photos, then hand the user an honest instruction.
///
/// **There is no public API to set the wallpaper on iOS.** Not a private one worth shipping, not a
/// shortcut, not an entitlement. The job genuinely ends outside the app, so the button is called
/// *Save for Wallpaper* and the sheet says who does what. Dressing this up as though the app changed
/// the wallpaper would be the single most damaging thing the app could do to its own credibility.
@MainActor
@Observable
final class IOSWallpaperActions: WallpaperActions {

    var handoff: WallpaperHandoff?

    let primaryActionTitle = "Save for Wallpaper"

    func performPrimary(on record: WallpaperRecord) async {
        // Add-only authorisation: the app writes one picture and never reads the library, so asking
        // for read access would be asking for something it does not use.
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            handoff = WallpaperHandoff(
                succeeded: false,
                message: "Photos access is off for this app, so the wallpaper couldn't be saved there. You can turn it on in Settings → Privacy → Photos.")
            return
        }

        do {
            // The library holds the uncropped master; Photos gets the copy shaped for *this*
            // screen. Cropping here rather than at generation is what lets the same wallpaper be
            // fitted again, differently, on an iPad or a Mac.
            // Off the main actor: `fitNatively` runs the upscaler over the cropped strip — about
            // thirty tiles — and doing that on the actor that handled the tap freezes the app for
            // several seconds, which reads as a hang.
            let panel = WallpaperFitting.currentScreenSize()
            let data = try await Task.detached(priority: .userInitiated) {
                try Self.fitted(record, to: panel)
            }.value
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
            handoff = WallpaperHandoff(succeeded: true, message: "")
        } catch {
            handoff = WallpaperHandoff(succeeded: false,
                                       message: "The wallpaper couldn't be added to Photos just now.")
        }
    }

    func share(_ record: WallpaperRecord) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.keyWindow?.rootViewController
        else { return }

        let controller = UIActivityViewController(activityItems: [record.imageURL],
                                                  applicationActivities: nil)
        // iPad presents this as a popover and traps without an anchor.
        controller.popoverPresentationController?.sourceView = root.view
        controller.popoverPresentationController?.sourceRect =
            CGRect(x: root.view.bounds.midX, y: root.view.bounds.maxY - 80, width: 1, height: 1)
        root.present(controller, animated: true)
    }

    func dismissHandoff() { handoff = nil }

    /// PNG of the master, fitted to the panel — cropped, enlarged by ESRGAN if the crop came out
    /// smaller than the screen, then resampled down to exactly the panel's pixels.
    ///
    /// Takes the panel as an argument rather than reading it, because `currentScreenSize()` is
    /// main-actor isolated and this deliberately runs off the main actor: the upscaler's thirty-odd
    /// tiles on the tap's own thread is a multi-second freeze, which reads as a hang.
    nonisolated private static func fitted(_ record: WallpaperRecord, to panel: AspectRatio) throws -> Data {
        let original = try Data(contentsOf: record.imageURL)
        guard let image = Bitmap.platformImage(pngData: original)?.cgImage,
              let fitted = WallpaperFitting.fitNatively(image, to: panel),
              let png = Bitmap.pngData(cg: fitted)
        else {
            // Better the uncropped master in Photos than nothing at all — iOS's own wallpaper
            // picker will let the user position it.
            return original
        }
        return png
    }
}

/// The mandatory honesty sheet (bundle `1c`).
///
/// It says what happened, then exactly what the user has to do — three steps, about ten seconds. It
/// never claims the wallpaper was set.
struct HandoffSheet: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    var handoff: WallpaperHandoff

    var body: some View {
        VStack(alignment: .leading, spacing: WP.Space.margin) {
            if handoff.succeeded {
                Label {
                    Text("Saved to Photos").wpFont(.cardHeading)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(WP.success(scheme))
                }
                .foregroundStyle(WP.ink(scheme))

                Text("iPhone doesn't let apps change the wallpaper — that last step is yours, and it takes about ten seconds:")
                    .wpFont(.body)
                    .foregroundStyle(WP.ink2(scheme))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: WP.Space.gap) {
                    step(1, "Settings → Wallpaper")
                    step(2, "Add New Wallpaper → Photos")
                    step(3, "It's the most recent picture — tap it")
                }
            } else {
                Text("Not saved")
                    .wpFont(.cardHeading)
                    .foregroundStyle(WP.ink(scheme))
                Text(handoff.message)
                    .wpFont(.body)
                    .foregroundStyle(WP.ink2(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Settings' own app page is as far as any app may deep-link; there is no public URL for
            // Settings → Wallpaper. The three steps above are what actually gets the user there.
            PrimaryCapsuleButton(title: "Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                dismiss()
            }
        }
        .padding(WP.Space.section)
        .presentationDetents([.height(430)])
        .presentationBackground(.clear)
        .background {
            RoundedRectangle(cornerRadius: WP.Radius.sheet, style: .continuous)
                .fill(.clear)
                .wpGlassCard(radius: WP.Radius.sheet)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: WP.Space.gap) {
            Text("\(number)")
                .wpFont(.caption, tabularNumbers: true)
                .foregroundStyle(WP.ink3(scheme))
                .frame(width: 18, alignment: .trailing)
            Text(text)
                .wpFont(.secondary)
                .foregroundStyle(WP.ink(scheme))
        }
    }
}
#endif
