import AVFoundation
import Foundation
import RedesignKit
import SwiftUI

/// What the capture screen drives.
///
/// A protocol with three implementations, because "take a photo" means three genuinely different
/// things here: a real camera with depth on a device, a bundled sample in the Simulator, and an
/// open panel on the Mac. The screen does not branch on any of that — it asks for a shot.
@MainActor
protocol CameraSession: AnyObject {
    /// False when there is no camera at all — the Mac, and a device where access was denied. The
    /// shutter and the flip button hide, and import becomes the only door.
    var canCapture: Bool { get }
    var canSwitchCamera: Bool { get }
    /// The live coach reading, or nil when there is no live preview to read.
    var coach: CoachLine? { get }

    func start(mode: DirectionMode) async
    func stop()
    func setMode(_ mode: DirectionMode)
    func switchCamera()
    func capture() async throws -> SourceShot
}

enum CaptureError: Error {
    case unavailable
    case denied
    case failed
}

enum CameraSessionFactory {
    /// Three implementations, one decision point.
    ///
    /// Denied authorisation is deliberately NOT an error screen. Somebody who declined the camera
    /// can still redesign a photo they already have, so it degrades to the import-only session —
    /// a supported configuration rather than a dead end with a link to Settings.
    @MainActor
    static func make() -> any CameraSession {
        #if os(macOS)
        return ImportOnlySession()
        #elseif targetEnvironment(simulator)
        return SimulatedCameraSession()
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted: return ImportOnlySession()
        default: return AVCameraSession()
        }
        #endif
    }
}

/// No camera: the Mac, and any device where access was declined.
@MainActor
final class ImportOnlySession: CameraSession {
    var canCapture: Bool { false }
    var canSwitchCamera: Bool { false }
    var coach: CoachLine? { nil }

    func start(mode: DirectionMode) async {}
    func stop() {}
    func setMode(_ mode: DirectionMode) {}
    func switchCamera() {}
    func capture() async throws -> SourceShot { throw CaptureError.unavailable }
}

/// The Simulator has no camera, and a capture screen that cannot be reached in the Simulator is a
/// capture screen no UI test can drive.
///
/// The preview is a bundled sample photo, the shutter returns it with synthetic depth, and the
/// coach line CYCLES through its faults so both the green and the amber branch are reachable by
/// eye as well as by assertion.
///
/// ⚠️ The sample photos are labelled sample photos. They must never appear in a store screenshot
/// as a *result* — same rule as the Mock configuration.
@MainActor
final class SimulatedCameraSession: CameraSession {
    var canCapture: Bool { true }
    var canSwitchCamera: Bool { false }
    private(set) var coach: CoachLine?

    private var mode: DirectionMode = .interior
    private var tick = 0
    private var timer: Timer?

    func start(mode: DirectionMode) async {
        self.mode = mode
        coach = CoachLine(mode: mode, fault: .none)
        let timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advance() }
        }
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func setMode(_ mode: DirectionMode) {
        self.mode = mode
        coach = CoachLine(mode: mode, fault: coach?.fault ?? .none)
    }

    func switchCamera() {}

    private func advance() {
        let faults: [CoachLine.Fault] = [.none, .none, .tilted, .none, .tooClose, .none, .tooDark]
        tick = (tick + 1) % faults.count
        coach = CoachLine(mode: mode, fault: faults[tick])
    }

    func capture() async throws -> SourceShot {
        guard let data = SampleAssets.photoData(for: mode),
              let size = SampleAssets.pixelSize(of: data) else {
            throw CaptureError.failed
        }
        let depthSize = PixelSize(width: 256, height: 256)
        return SourceShot(mode: mode,
                          imageData: data,
                          pixelSize: size,
                          depthValues: DepthSource.synthetic(size: depthSize),
                          depthSize: depthSize,
                          provenance: .synthetic)
    }
}
