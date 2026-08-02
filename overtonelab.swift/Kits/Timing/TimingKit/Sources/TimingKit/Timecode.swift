import Foundation

public struct Timecode: Sendable, Equatable {
    public var hours, minutes, seconds, frames: Int
    public init(hours: Int, minutes: Int, seconds: Int, frames: Int) {
        self.hours = hours; self.minutes = minutes; self.seconds = seconds; self.frames = frames
    }
    public var label: String { String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames) }
}

/// SMPTE ST 12-1 timecode ↔ frame count for 24 / 25 / 30 fps (non-drop) and 29.97 drop-frame.
/// Drop-frame is represented with `fps = 30` + `dropFrame = true` (the label rate).
public enum SMPTE {
    /// Frame count for a timecode.
    public static func frameCount(_ tc: Timecode, fps: Int, dropFrame: Bool = false) -> Int {
        let base = ((tc.hours * 60 + tc.minutes) * 60 + tc.seconds) * fps + tc.frames
        guard dropFrame else { return base }
        let dropPerMinute = 2
        let totalMinutes = 60 * tc.hours + tc.minutes
        return base - dropPerMinute * (totalMinutes - totalMinutes / 10)
    }

    /// Timecode for a frame count.
    public static func timecode(frameCount n: Int, fps: Int, dropFrame: Bool = false) -> Timecode {
        var f = n
        if dropFrame {
            let dropFrames = 2
            let framesPer10Min = 17982   // 30·60·10 − 9·2
            let framesPerMin = 1798      // 30·60 − 2
            let d = f / framesPer10Min
            let m = f % framesPer10Min
            if m > dropFrames {
                f += dropFrames * 9 * d + dropFrames * ((m - dropFrames) / framesPerMin)
            } else {
                f += dropFrames * 9 * d
            }
        }
        let fr = f % fps
        let s = (f / fps) % 60
        let mi = (f / (fps * 60)) % 60
        let h = (f / (fps * 3600)) % 24
        return Timecode(hours: h, minutes: mi, seconds: s, frames: fr)
    }
}
