//
//  SoundManager.swift
//  froggo.swift
//
//  Created by Oleksandr Koreniuk on 19.09.2025.
//

import Foundation
import AVFoundation
import Combine

class SoundManager: ObservableObject {
    static let shared = SoundManager()

    @Published var isMuted: Bool {
        didSet {
            UserDefaults.standard.set(isMuted, forKey: "mute")
            // Stop all sounds when muted
            if isMuted {
                stopAllSounds()
            }
        }
    }

    // Dictionary to hold audio players for different sounds
    private var audioPlayers: [String: AVAudioPlayer] = [:]
    private var loopingPlayers: Set<String> = []

    private init() {
        // Load mute setting, default to unmuted (true = unmuted in Unity)
        self.isMuted = !UserDefaults.standard.bool(forKey: "mute")
    }

    func playSound(_ soundName: String, loop: Bool = false) {
        guard !isMuted else { return }

        // Map sound names to actual file names
        let soundFiles: [String: String] = [
            "frog_jump": "jump",
            "frog_land": "landing",
            "fly_eaten": "fly_eaten",
            "frog_die": "game_over",
            "frog_spawn": "game_started",
            "fly": "fly",
            "button_clicked": "button_clicked",
            "cityscape": "cityscape"
        ]

        guard let fileName = soundFiles[soundName] else {
            print("Sound not found: \(soundName)")
            return
        }

        // Check if we already have this player
        if let existingPlayer = audioPlayers[soundName] {
            existingPlayer.currentTime = 0
            existingPlayer.numberOfLoops = loop ? -1 : 0
            existingPlayer.play()
            if loop { loopingPlayers.insert(soundName) }
            return
        }

        // Load the sound file
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "wav") ??
                        Bundle.main.url(forResource: fileName, withExtension: "mp3") else {
            print("Sound file not found: \(fileName)")
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = loop ? -1 : 0
            player.prepareToPlay()
            player.play()
            audioPlayers[soundName] = player
            if loop { loopingPlayers.insert(soundName) }
        } catch {
            print("Error playing sound \(soundName): \(error.localizedDescription)")
        }
    }

    func stopSound(_ soundName: String) {
        audioPlayers[soundName]?.stop()
        loopingPlayers.remove(soundName)
    }

    func stopAllSounds() {
        for player in audioPlayers.values {
            player.stop()
        }
        loopingPlayers.removeAll()
    }

    func playJumpSound() {
        playSound("frog_jump")
    }

    func playLandSound() {
        playSound("frog_land")
    }

    func playFlyEatenSound() {
        playSound("fly_eaten")
    }

    func playGameOverSound() {
        playSound("frog_die")
    }

    func playSpawnSound() {
        playSound("frog_spawn")
    }

    func playBackgroundMusic() {
        playSound("cityscape", loop: true)
    }

    func stopBackgroundMusic() {
        stopSound("cityscape")
    }
}
