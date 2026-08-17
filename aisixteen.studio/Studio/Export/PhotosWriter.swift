import Foundation
import Photos
import RecipeKit

/// Puts the enhanced copy in the user's photo library — and nothing else.
///
/// ⚠️ **Add-only.** `PHAccessLevel.addOnly` is the whole authorisation this app ever requests: it
/// can put a new photo in, and it cannot read, edit or delete anything that was already there. That
/// is not caution for its own sake — it is what makes "your original is never touched" a property of
/// the system rather than a promise in a marketing string.
enum PhotosWriter {

    enum WriteError: Error, Equatable {
        case notAuthorised
        case failed(String)
    }

    /// Asks only at the moment of saving, never at launch — a permission sheet on first run, before
    /// the app has done anything, is how an app teaches people to say no.
    static func saveAsNewPhoto(_ data: Data) async throws {
        let status = await requestAddOnlyAccess()
        guard status == .authorized || status == .limited else { throw WriteError.notAuthorised }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = "Enhanced.heic"
                request.addResource(with: .photo, data: data, options: options)
            }
        } catch {
            throw WriteError.failed(error.localizedDescription)
        }
    }

    private static func requestAddOnlyAccess() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard current == .notDetermined else { return current }
        return await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    }

    /// What to say when the user has said no. It names the setting, and it does not sulk: the app
    /// still works, the copy is still in their iCloud folder, and Share is still there.
    static let deniedMessage = """
        Studio can't add to your photo library. You can turn that on in Settings, \
        or use Share — the enhanced copy is already in your iCloud folder either way.
        """
}
