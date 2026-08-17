import AVFoundation
import Foundation

/// The one audio surface: an AVAudioEngine with a music bus, an sfx bus, and Apple's
/// peak limiter on the master mix (the managed AUPeakLimiter — no hand-rolled DSP), so a
/// bell landing on top of the bed can never clip the output.
///
///     musicPlayer ─ musicMixer ─┐
///                               ├─ mainMixer ─ limiter ─ output
///     sfx pool ──── sfxMixer  ──┘
///
/// Like the renderer, this layer is a dumb executor: the decisions (what plays when, at
/// what target volume) come from AppModel and the pure AudioPlan; this file only owns
/// nodes, buffers and fades.
@MainActor
final class AudioController {

    private let engine = AVAudioEngine()
    private let musicPlayer = AVAudioPlayerNode()
    private let musicMixer = AVAudioMixerNode()
    private let sfxMixer = AVAudioMixerNode()
    private var sfxPlayers: [AVAudioPlayerNode] = []
    private var nextSFXPlayer = 0
    private let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0, componentFlagsMask: 0))

    private var sfxBuffers: [GameSound: AVAudioPCMBuffer] = [:]
    private var musicBuffer: AVAudioPCMBuffer?
    private var fadeTask: Task<Void, Never>?
    private(set) var started = false

    /// Gate checked at play time — flipping it mid-session simply silences future sounds.
    var soundsEnabled = true

    /// Idempotent; call from sceneRemade() (the same lifecycle seam the renderer and
    /// haptics use). A failed engine start leaves a silent, harmless controller.
    func prepare() {
        guard !started else { return }
        #if os(iOS)
        // .ambient: the séance bed yields to the reader's own music and respects the
        // silent switch — a toy must never fight the phone.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        loadBuffers()

        engine.attach(sfxMixer)
        engine.attach(limiter)
        // The music bus exists only when a bed is bundled — BGM is currently parked
        // (AppModel.musicFeatureEnabled); the engine must run for sfx regardless.
        if let musicBuffer {
            engine.attach(musicPlayer)
            engine.attach(musicMixer)
            engine.connect(musicPlayer, to: musicMixer, format: musicBuffer.format)
            engine.connect(musicMixer, to: engine.mainMixerNode, format: nil)
        }

        let sfxFormat = sfxBuffers.values.first?.format
        for _ in 0..<4 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: sfxMixer, format: sfxFormat)
            sfxPlayers.append(player)
        }
        engine.connect(sfxMixer, to: engine.mainMixerNode, format: nil)

        // The limiter sits on the MASTER: mainMixer → limiter → hardware. Connecting the
        // main mixer explicitly replaces the implicit mixer→output wiring.
        engine.connect(engine.mainMixerNode, to: limiter, format: nil)
        engine.connect(limiter, to: engine.outputNode, format: nil)

        engine.prepare()
        do { try engine.start() } catch { return }

        if let musicBuffer {
            musicMixer.outputVolume = 0
            musicPlayer.scheduleBuffer(musicBuffer, at: nil, options: .loops)
            musicPlayer.play()
        }
        started = true
    }

    /// Fade the bed toward AudioPlan's target. Fade-in is slower than fade-out on purpose
    /// (arriving is an entrance; leaving must get out of the way).
    func setMusicVolume(target: Double) {
        guard started else { return }
        fadeTask?.cancel()
        let from = Double(musicMixer.outputVolume)
        guard abs(from - target) > 0.001 else { return }
        let seconds = target > from ? 2.2 : 0.9
        fadeTask = Task { [musicMixer] in
            let steps = max(Int(seconds * 60), 1)
            for i in 1...steps {
                if Task.isCancelled { return }
                let t = Double(i) / Double(steps)
                let eased = t * t * (3 - 2 * t)
                musicMixer.outputVolume = Float(from + (target - from) * eased)
                try? await Task.sleep(nanoseconds: UInt64(seconds / Double(steps) * 1_000_000_000))
            }
        }
    }

    func play(_ sound: GameSound) {
        guard started, soundsEnabled, let buffer = sfxBuffers[sound] else { return }
        let player = sfxPlayers[nextSFXPlayer]
        nextSFXPlayer = (nextSFXPlayer + 1) % sfxPlayers.count
        player.stop()
        player.volume = sound.gain
        player.scheduleBuffer(buffer, at: nil)
        player.play()
    }

    private func loadBuffers() {
        musicBuffer = Self.buffer(resource: "bgm_arcana", ext: "m4a")
        for sound in GameSound.allCases {
            sfxBuffers[sound] = Self.buffer(resource: sound.rawValue, ext: "caf")
        }
    }

    private static func buffer(resource: String, ext: String) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext),
              let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length))
        else { return nil }
        do { try file.read(into: buffer) } catch { return nil }
        return buffer
    }
}
