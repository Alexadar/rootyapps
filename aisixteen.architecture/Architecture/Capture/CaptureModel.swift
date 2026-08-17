import Foundation
import Observation
import RedesignKit
import SwiftUI

/// The capture screen's state.
///
/// `CaptureView` shipped `mode`, `coach` and `shotUsable` as local `@State` — `coach` and
/// `shotUsable` were constants that nothing ever mutated, and `mode` could not be read by anything
/// downstream, which is why `DirectionView` had to hardcode `.interior`. All three live here now,
/// and `mode` travels on the `SourceShot`.
@MainActor
@Observable
final class CaptureModel {

    var mode: DirectionMode = .interior {
        didSet {
            guard mode != oldValue else { return }
            session.setMode(mode)
        }
    }

    private(set) var isCapturing = false
    private(set) var errorMessage: String?

    @ObservationIgnored private(set) var session: any CameraSession

    init(session: (any CameraSession)? = nil) {
        self.session = session ?? CameraSessionFactory.make()
    }

    /// The live coach reading, or the idle line when there is no camera to read from.
    var coach: CoachLine {
        session.coach ?? CoachLine(mode: mode, fault: .none)
    }

    var canCapture: Bool { session.canCapture }
    var canSwitchCamera: Bool { session.canSwitchCamera }

    func start() async {
        await session.start(mode: mode)
    }

    func stop() {
        session.stop()
    }

    func switchCamera() {
        session.switchCamera()
    }

    func capture() async -> SourceShot? {
        guard !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }
        do {
            return try await session.capture()
        } catch {
            errorMessage = "That photo couldn't be taken. Try again."
            return nil
        }
    }

    func imported(from url: URL) -> SourceShot? {
        do {
            return try PhotoImport.shot(from: url, mode: mode)
        } catch {
            errorMessage = "That photo couldn't be read."
            return nil
        }
    }

    func imported(data: Data) -> SourceShot? {
        guard let size = SampleAssets.pixelSize(of: data) else {
            errorMessage = "That photo couldn't be read."
            return nil
        }
        return PhotoImport.shot(from: data, pixelSize: size, url: nil, mode: mode)
    }

    func clearError() { errorMessage = nil }
}
