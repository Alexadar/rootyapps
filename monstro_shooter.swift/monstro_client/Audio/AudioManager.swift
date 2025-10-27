import Foundation
import AVFoundation

/// Audio manager singleton to handle background music and sound effects
class AudioManager: NSObject, AVAudioPlayerDelegate {
    static let shared = AudioManager()

    // Audio players
    private var bgmPlayer: AVAudioPlayer?
    private var sfxPlayers: [AVAudioPlayer] = []

    // Music categories
    private let menuMusic = ["menu_1.mp3", "menu_2.mp3"]
    private let fightMusic = ["fight_1.mp3", "fight_2.mp3"]

    // Weapon SFX files
    private let pistolSound = "weapon_pistol.wav"
    private let reloadSound = "weapon_reload.wav"

    private var currentMusicType: MusicType?

    // Audio settings (loaded from SettingsManager)
    private var bgmEnabled: Bool
    private var sfxEnabled: Bool

    enum MusicType {
        case menu
        case fight
    }

    private override init() {
        // Load settings from persistent storage
        self.bgmEnabled = SettingsManager.shared.bgmEnabled
        self.sfxEnabled = SettingsManager.shared.sfxEnabled

        super.init()

        print("[AudioManager] Initialized with BGM: \(bgmEnabled), SFX: \(sfxEnabled)")

        // Configure audio session for game audio
        do {
            #if os(macOS)
            // macOS doesn't need audio session configuration
            #else
            // Use .playback category for game audio (stops other audio, continues in background if needed)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            print("[AudioManager] Audio session configured successfully")
            #endif
        } catch {
            print("[AudioManager] Failed to set up audio session: \(error)")
        }
    }

    // MARK: - Background Music

    /// Play random menu music
    func playMenuMusic() {
        playMusic(type: .menu)
    }

    /// Play random fight music
    func playFightMusic() {
        playMusic(type: .fight)
    }

    /// Stop current background music
    func stopMusic() {
        bgmPlayer?.stop()
        bgmPlayer = nil
        currentMusicType = nil
    }

    /// Enable or disable background music
    func setBGMEnabled(_ enabled: Bool) {
        bgmEnabled = enabled
        SettingsManager.shared.bgmEnabled = enabled  // Save to persistent storage

        if !enabled {
            bgmPlayer?.pause()
        } else if let player = bgmPlayer, currentMusicType != nil {
            player.play()
        }
    }

    /// Enable or disable sound effects
    func setSFXEnabled(_ enabled: Bool) {
        sfxEnabled = enabled
        SettingsManager.shared.sfxEnabled = enabled  // Save to persistent storage
    }

    private func playMusic(type: MusicType) {
        // Don't play music if BGM is disabled
        guard bgmEnabled else {
            print("[AudioManager] BGM is disabled, skipping music playback")
            return
        }

        // Stop previous music if switching types
        if currentMusicType != type {
            stopMusic()
        }

        // Don't restart if already playing same type
        if currentMusicType == type && bgmPlayer?.isPlaying == true {
            return
        }

        currentMusicType = type

        let musicFiles = type == .menu ? menuMusic : fightMusic
        guard let randomMusic = musicFiles.randomElement() else {
            print("[AudioManager] ERROR: No music files in category")
            return
        }

        print("[AudioManager] Selected random music from \(musicFiles): \(randomMusic)")

        let resourceName = randomMusic.replacingOccurrences(of: ".mp3", with: "")

        // Try to find in BGM subdirectory first
        var url = Bundle.main.url(forResource: resourceName, withExtension: "mp3", subdirectory: "Assets/Audio/BGM")

        // Fallback: search in root
        if url == nil {
            url = Bundle.main.url(forResource: resourceName, withExtension: "mp3")
        }

        guard let fileURL = url else {
            print("[AudioManager] ERROR: Could not find music file: \(randomMusic)")
            print("[AudioManager] Searched in: Assets/Audio/BGM and root")
            print("[AudioManager] Available mp3 files: \(Bundle.main.urls(forResourcesWithExtension: "mp3", subdirectory: nil)?.map { $0.lastPathComponent } ?? [])")
            return
        }

        print("[AudioManager] Found music file at: \(fileURL.path)")

        do {
            bgmPlayer = try AVAudioPlayer(contentsOf: fileURL)
            bgmPlayer?.numberOfLoops = 0 // Play once, then cycle to next track
            bgmPlayer?.volume = 0.5 // 50% volume
            bgmPlayer?.delegate = self
            bgmPlayer?.prepareToPlay()

            let success = bgmPlayer?.play() ?? false
            if success {
                print("[AudioManager] SUCCESS: Now playing \(type == .menu ? "menu" : "fight") music: \(randomMusic)")
            } else {
                print("[AudioManager] ERROR: Failed to start playback of \(randomMusic)")
            }
        } catch {
            print("[AudioManager] ERROR: Failed to create audio player: \(error)")
        }
    }

    // MARK: - Sound Effects

    /// Play random sound from an array of sound filenames
    func playRandomSound(from soundFiles: [String]) {
        guard let randomSound = soundFiles.randomElement() else { return }
        playSFX(filename: randomSound)
    }

    /// Play pistol sound for player shooting
    func playPistolSound() {
        playSFX(filename: pistolSound)
    }

    /// Play reload sound for weapon reloading
    func playReloadSound() {
        playSFX(filename: reloadSound)
    }

    private func playSFX(filename: String) {
        guard sfxEnabled else { return }

        let resourceName = filename.replacingOccurrences(of: ".wav", with: "")

        // Try to find in SFX subdirectory first
        var url = Bundle.main.url(forResource: resourceName, withExtension: "wav", subdirectory: "Assets/Audio/SFX")

        // Fallback: search in root
        if url == nil {
            url = Bundle.main.url(forResource: resourceName, withExtension: "wav")
        }

        guard let fileURL = url else {
            print("[AudioManager] ERROR: Could not find SFX file: \(filename)")
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: fileURL)
            player.volume = 0.3 // 30% volume for SFX
            player.prepareToPlay()
            player.play()

            // Keep reference to player and clean up when done
            sfxPlayers.append(player)

            // Clean up finished players
            DispatchQueue.main.asyncAfter(deadline: .now() + player.duration + 0.1) { [weak self] in
                self?.sfxPlayers.removeAll { $0 == player }
            }
        } catch {
            print("Failed to play SFX: \(error)")
        }
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard flag, player == bgmPlayer, let musicType = currentMusicType else { return }

        print("[AudioManager] Track finished, playing next random track")

        // Play next random track of the same type
        playMusic(type: musicType)
    }
}
