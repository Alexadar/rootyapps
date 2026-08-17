import SwiftUI
import PhotosUI
import RecipeKit

/// The empty state (`1a`).
///
/// Two ways in on the phone, three on the Mac (drag-and-drop is added by the Mac shell). The privacy
/// line at the bottom is the positioning, stated once, plainly, exactly where a competitor would put
/// a paywall.
struct ImportView: View {

    @Environment(\.colorScheme) private var scheme

    @State private var selection: PhotosPickerItem?
    @State private var isShowingCamera = false
    var onPicked: (Data, String) -> Void

    var body: some View {
        VStack(spacing: ST.Space.section) {
            Spacer()

            VStack(spacing: ST.Space.gap) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(ST.accent.opacity(0.75))

                Text("Bring a photo.")
                    .stFont(.screenTitle)
                    .foregroundStyle(ST.ink(scheme))

                Text("Studio improves a photo you already have — right here, on this \(Self.deviceNoun).")
                    .stFont(.body)
                    .foregroundStyle(ST.ink2(scheme))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            VStack(spacing: ST.Space.gap) {
                // PhotosPicker runs out of process, so choosing a photo needs **no permission at
                // all** — no prompt, no Settings trip, and the app genuinely cannot read the rest of
                // the library. That is not a technicality; it is most of the privacy promise.
                PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
                    Text("Choose from Library")
                        .stFont(.button)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: ST.primaryCapsuleHeight)
                }
                .buttonStyle(.plain)
                .stGlassCapsule(.tinted)
                .accessibilityIdentifier("import.library")

                #if os(iOS)
                Button {
                    isShowingCamera = true
                } label: {
                    Text("Take a Photo")
                        .stFont(.button)
                        .foregroundStyle(ST.ink(scheme))
                        .frame(maxWidth: .infinity)
                        .frame(height: ST.primaryCapsuleHeight)
                }
                .buttonStyle(.plain)
                .stGlassCapsule(.regular)
                .accessibilityIdentifier("import.camera")
                #endif
            }
            .frame(maxWidth: 340)

            Spacer()

            Text(PrivacyCopy.importFooter)
                .stFont(.footnote)
                .foregroundStyle(ST.ink3(scheme))
                .multilineTextAlignment(.center)
                .padding(.bottom, ST.Space.section)
                .accessibilityIdentifier("import.privacy")
        }
        .padding(.horizontal, ST.Space.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: ST.canvasGradient, startPoint: .top, endPoint: .bottom))
        .onChange(of: selection) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                onPicked(data, Self.name(for: item))
                selection = nil
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { data in
                isShowingCamera = false
                guard let data else { return }
                onPicked(data, "Photo")
            }
        }
        #endif
    }

    private static var deviceNoun: String {
        #if os(macOS)
        "Mac"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }

    /// The picker gives a supported-type list and sometimes an item identifier, never the original
    /// filename — so the library falls back to something the user will still recognise.
    private static func name(for item: PhotosPickerItem) -> String {
        item.itemIdentifier.map { String($0.prefix(8)) }.map { "Photo \($0)" } ?? "Photo"
    }
}

#if os(iOS)
import UIKit

/// The camera, wrapped.
///
/// `UIImagePickerController` rather than a `PhotosPicker` source: this is a capture, not a
/// selection, and it hands back the image without ever writing it to the library — which matters,
/// because a photo the app created and then enhanced would otherwise leave two files behind where
/// the user expected one.
struct CameraPicker: UIViewControllerRepresentable {

    var onFinish: (Data?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera)
            ? .camera : .photoLibrary
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onFinish: (Data?) -> Void
        init(onFinish: @escaping (Data?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            // HEIC where possible, so a capture is stored the way the camera would have stored it.
            let data = image?.cgImage.flatMap { ImageCoder.encode($0) }
            onFinish(data)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
#endif
