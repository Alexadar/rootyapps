import Foundation
import Combine
import TimingKit

@MainActor
final class TimecodeViewModel: ObservableObject {
    @Published var fps = 30
    @Published var dropFrame = false

    var effectiveFps: Double { dropFrame ? 30000.0 / 1001.0 : Double(fps) }

    // Frames → timecode
    @Published var frameCount = 108000.0
    var timecodeLabel: String { SMPTE.timecode(frameCount: Int(frameCount), fps: fps, dropFrame: dropFrame).label }
    var frameSeconds: Double { Double(frameCount) / effectiveFps }

    // Timecode → frames
    @Published var h = 1
    @Published var m = 0
    @Published var s = 0
    @Published var f = 0
    var frames: Int { SMPTE.frameCount(Timecode(hours: h, minutes: m, seconds: s, frames: f), fps: fps, dropFrame: dropFrame) }
    var tcSeconds: Double { Double(frames) / effectiveFps }
}
