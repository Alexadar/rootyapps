#if os(iOS)
import SwiftUI
import VisionKit

/// VisionKit document camera. Opens ONLY from an explicit tap (never at launch).
/// VNDocumentCameraViewController hands back perspective-corrected page images.
struct CameraScanView: UIViewControllerRepresentable {
    let onFinish: ([CGImage]) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: CameraScanView
        init(_ parent: CameraScanView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            var pages: [CGImage] = []
            for i in 0..<scan.pageCount {
                if let cg = scan.imageOfPage(at: i).cgImage { pages.append(cg) }
            }
            parent.onFinish(pages)
            parent.dismiss()
        }

        func documentCameraViewControllerDidCancel(_: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        func documentCameraViewController(_: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            parent.dismiss()
        }
    }
}
#endif
