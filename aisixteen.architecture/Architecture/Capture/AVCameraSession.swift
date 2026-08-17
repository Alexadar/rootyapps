#if os(iOS) && !targetEnvironment(simulator)
import AVFoundation
import CoreMotion
import Foundation
import RedesignKit
import UIKit

/// The real camera, with real depth.
///
/// This is not mocked and does not need to be: LiDAR and dual-camera parallax are Apple
/// frameworks, not models. The only mocked thing in the whole depth story is monocular estimation
/// from a flat photo, which genuinely is a neural network and genuinely does not exist yet.
@MainActor
final class AVCameraSession: NSObject, CameraSession {

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let motion = CMMotionManager()
    private var device: AVCaptureDevice?
    private var mode: DirectionMode = .interior
    private var usingFrontCamera = false
    private var continuation: CheckedContinuation<SourceShot, Error>?
    /// The last depth frame's 95th-percentile disparity, for the coach's distance axis.
    private var nearestDisparity: Float?

    private(set) var coach: CoachLine?

    var canCapture: Bool { true }
    var canSwitchCamera: Bool {
        // Hidden rather than disabled when there is nothing to switch to — a control that does
        // nothing is worse than no control.
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInTrueDepthCamera],
            mediaType: .video, position: .unspecified).devices.count > 1
    }

    /// The preview layer the SwiftUI view wraps.
    var previewSession: AVCaptureSession { session }

    // ── lifecycle ────────────────────────────────────────────────────────────────────────────

    func start(mode: DirectionMode) async {
        self.mode = mode
        guard await requestAccess() else { return }
        configure()
        startMotion()
        // `startRunning` blocks — on a cold start it can take the better part of a second, and on
        // the main actor that is a frozen shutter button the user is already pressing.
        let session = self.session
        await Task.detached(priority: .userInitiated) { session.startRunning() }.value
    }

    func stop() {
        session.stopRunning()
        motion.stopDeviceMotionUpdates()
    }

    func setMode(_ mode: DirectionMode) {
        self.mode = mode
        recomputeCoach()
    }

    func switchCamera() {
        usingFrontCamera.toggle()
        configure()
    }

    private func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    private func configure() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.inputs.forEach { session.removeInput($0) }
        session.sessionPreset = .photo

        // Best depth first. A LiDAR device measures the room; a dual camera infers it from
        // parallax; a plain wide angle gives nothing and the shot falls back to estimation.
        let position: AVCaptureDevice.Position = usingFrontCamera ? .front : .back
        let preferred: [AVCaptureDevice.DeviceType] = usingFrontCamera
            ? [.builtInTrueDepthCamera, .builtInWideAngleCamera]
            : [.builtInLiDARDepthCamera, .builtInDualCamera, .builtInDualWideCamera,
               .builtInTripleCamera, .builtInWideAngleCamera]

        let discovered = AVCaptureDevice.DiscoverySession(deviceTypes: preferred,
                                                          mediaType: .video,
                                                          position: position).devices
        guard let device = preferred.compactMap({ type in
            discovered.first { $0.deviceType == type }
        }).first,
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        self.device = device
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }

        // Depth has to be enabled on the OUTPUT before it is requested per-photo; asking for it
        // only at capture time silently returns a photo with no depth attached.
        photoOutput.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported
    }

    // ── the coach ────────────────────────────────────────────────────────────────────────────

    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 10
        motion.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            MainActor.assumeIsolated {
                self?.absorbMotion(motion)
            }
        }
    }

    private var roll: Double = 0
    private var pitch: Double = 0

    private func absorbMotion(_ motion: CMDeviceMotion) {
        roll = motion.attitude.roll * 180 / .pi
        // Held up at a wall the phone is vertical, so pitch is measured from there rather than
        // from flat — otherwise the coach reads "hold level" for the entire session.
        pitch = (motion.attitude.pitch * 180 / .pi) - 90
        recomputeCoach()
    }

    private func recomputeCoach() {
        let light: Double
        if let device {
            // ISO relative to the device's own range: a usable stand-in for "is there enough
            // light" that needs no metering pass of its own.
            let range = device.activeFormat.maxISO - device.activeFormat.minISO
            light = range > 0 ? 1 - Double((device.iso - device.activeFormat.minISO) / range) : 1
        } else {
            light = 1
        }
        coach = CoachLine.evaluate(mode: mode,
                                   roll: roll,
                                   pitch: pitch,
                                   nearestDisparity: nearestDisparity,
                                   relativeLight: light)
    }

    // ── capture ──────────────────────────────────────────────────────────────────────────────

    func capture() async throws -> SourceShot {
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        settings.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliveryEnabled
        // Embed it as well as deliver it, so the file the app stores carries its own depth and
        // stays meaningful if it is ever exported.
        settings.embedsDepthDataInPhoto = settings.isDepthDataDeliveryEnabled

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension AVCameraSession: AVCapturePhotoCaptureDelegate {

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        let data = photo.fileDataRepresentation()
        let depth = photo.depthData
        let dimensions = photo.resolvedSettings.photoDimensions

        Task { @MainActor [weak self] in
            guard let self, let continuation = self.continuation else { return }
            self.continuation = nil

            guard error == nil, let data else {
                continuation.resume(throwing: CaptureError.failed)
                return
            }

            var values: [Float] = []
            var depthSize = PixelSize(width: 0, height: 0)
            var provenance = DepthProvenance.estimated

            if let depth, let read = DepthSource.values(from: depth) {
                values = read.values
                depthSize = read.size
                provenance = DepthSource.provenance(for: self.device)
                self.nearestDisparity = Self.percentile(read.values, 0.95)
            }

            continuation.resume(returning: SourceShot(
                mode: self.mode,
                imageData: data,
                pixelSize: PixelSize(width: Int(dimensions.width), height: Int(dimensions.height)),
                depthValues: values,
                depthSize: depthSize,
                provenance: provenance))
        }
    }

    /// The 95th percentile rather than the maximum: a single hot pixel or a speck of dust on the
    /// lens would otherwise decide that the user is standing too close to the wall.
    static func percentile(_ values: [Float], _ fraction: Double) -> Float? {
        let finite = values.filter { $0.isFinite }
        guard !finite.isEmpty else { return nil }
        let sorted = finite.sorted()
        let index = Int(Double(sorted.count - 1) * fraction)
        return sorted[index]
    }
}
#endif
