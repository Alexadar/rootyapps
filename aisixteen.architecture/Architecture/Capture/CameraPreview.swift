import AVFoundation
import SwiftUI

/// The live camera preview, or the closest honest thing to it.
///
/// The handoff's `CameraPreviewPlaceholder` was a `LinearGradient` declared in `CaptureView.swift`
/// and consumed from `DirectionView` and `GeneratingView` — a cross-file placeholder dependency
/// that had to be untangled before any of those screens could show a real photo.
struct CameraPreview: View {
    let session: any CameraSession

    var body: some View {
        #if os(iOS) && !targetEnvironment(simulator)
        if let camera = session as? AVCameraSession {
            AVPreviewLayerView(session: camera.previewSession)
        } else {
            SamplePreview(mode: .interior)
        }
        #else
        SamplePreview(mode: (session as? SimulatedCameraSession).map { _ in .interior } ?? .interior)
        #endif
    }
}

/// The Simulator's and the Mac's stand-in: the bundled sample photo, dimmed, with a label that
/// says what it is. A preview that silently looks like a camera feed when there is no camera is
/// the kind of thing that ends up in a screenshot.
struct SamplePreview: View {
    var mode: DirectionMode = .interior

    var body: some View {
        ZStack {
            if let url = SampleAssets.photoURL(for: mode),
               let image = Bitmap.thumbnail(contentsOf: url, maxPixel: 1400) {
                Image(platform: image)
                    .resizable()
                    .scaledToFill()
                    .fillAndClip()
            } else {
                LinearGradient(colors: [Color(hex: 0xB3A288), Color(hex: 0x75604A)],
                               startPoint: .top, endPoint: .bottom)
            }
            // A scrim top and bottom, because the shutter and the import button are white-on-photo
            // and a bright room photo leaves them invisible.
            LinearGradient(stops: [.init(color: .black.opacity(0.40), location: 0),
                                   .init(color: .black.opacity(0.05), location: 0.32),
                                   .init(color: .black.opacity(0.10), location: 0.70),
                                   .init(color: .black.opacity(0.48), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(alignment: .bottom) {
            Text("Sample photo — no camera here")
                .arcText(.micro)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, ARC.Space.gap)
                .padding(.vertical, 5)
                .background(Capsule().fill(.black.opacity(0.4)))
                .padding(.bottom, 128)
                .accessibilityIdentifier("capture.sampleNotice")
        }
    }
}

#if os(iOS) && !targetEnvironment(simulator)
private struct AVPreviewLayerView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.layer.session = session
        view.layer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        override var layer: AVCaptureVideoPreviewLayer {
            super.layer as! AVCaptureVideoPreviewLayer
        }
    }
}
#endif
