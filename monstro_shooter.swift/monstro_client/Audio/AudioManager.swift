import Foundation
import AVFoundation

/// Audio manager singleton to handle background music and sound effects
class AudioManager {
    static let shared = AudioManager()

    // Audio players
    private var bgmPlayer: AVAudioPlayer?
    private var sfxPlayers: [AVAudioPlayer] = []

    // Music categories
    private let menuMusic = ["menu_1.mp3", "menu_2.mp3"]
    private let fightMusic = ["fight_1.mp3", "fight_2.mp3"]

    // SFX files
    private let walkerSounds = ["monster_walker_1.wav", "monster_walker_2.wav"]
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

    private init() {
        // Load settings from persistent storage
        self.bgmEnabled = SettingsManager.shared.bgmEnabled
        self.sfxEnabled = SettingsManager.shared.sfxEnabled

        print("[AudioManager] Initialized with BGM: \(bgmEnabled), SFX: \(sfxEnabled)")

        // Configure audio session for simultaneous audio playback
        do {
            #if os(macOS)
            // macOS doesn't need audio session configuration
            #else
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
        } catch {
            print("Failed to set up audio session: \(error)")
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
        guard let randomMusic = musicFiles.randomElement() else { return }

        print("[AudioManager] Selected random music from \(musicFiles): \(randomMusic)")

        guard let url = Bundle.main.url(forResource: randomMusic.replacingOccurrences(of: ".mp3", with: ""),
                                       withExtension: "mp3") else {
            print("Could not find music file: \(randomMusic)")
            return
        }

        do {
            bgmPlayer = try AVAudioPlayer(contentsOf: url)
            bgmPlayer?.numberOfLoops = -1 // Loop indefinitely
            bgmPlayer?.volume = 0.5 // 50% volume
            bgmPlayer?.prepareToPlay()
            bgmPlayer?.play()
            print("Playing \(type == .menu ? "menu" : "fight") music: \(randomMusic)")
        } catch {
            print("Failed to play music: \(error)")
        }
    }

    // MARK: - Sound Effects

    /// Play random walker sound for berserker
    func playWalkerSound() {
        guard let randomSound = walkerSounds.randomElement() else { return }
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

        guard let url = Bundle.main.url(forResource: filename.replacingOccurrences(of: ".wav", with: ""),
                                       withExtension: "wav") else {
            print("Could not find SFX file: \(filename)")
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
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
}
