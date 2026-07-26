import Foundation
import Combine
import StereoKit

@MainActor
final class SRAViewModel: ObservableObject {
    @Published var pattern: Stereo.Pattern = .cardioid
    @Published var micAngle = 110.0
    @Published var spacing = 17.0
    @Published var speed = 343.0
    @Published var probe = 45.0

    var sra: Double { Stereo.recordingAngleDeg(micAngleDeg: micAngle, spacingCm: spacing, pattern: pattern, speed: speed) }
    var levelDiff: Double { Stereo.levelDifferenceDB(sourceDeg: probe, micAngleDeg: micAngle, pattern: pattern) }
    var timeDiff: Double { Stereo.timeDifferenceUs(sourceDeg: probe, spacingCm: spacing, speed: speed) }
    var nearest: Stereo.Preset { Stereo.nearestPreset(micAngleDeg: micAngle, spacingCm: spacing, pattern: pattern) }

    func sra(for preset: Stereo.Preset) -> Double {
        Stereo.recordingAngleDeg(micAngleDeg: preset.micAngleDeg, spacingCm: preset.spacingCm, pattern: preset.pattern, speed: speed)
    }
    func apply(_ preset: Stereo.Preset) {
        pattern = preset.pattern; micAngle = preset.micAngleDeg; spacing = preset.spacingCm
    }
}
