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
        }
    }
    
    private init() {
        self.isMuted = UserDefaults.standard.bool(forKey: "mute")
    }
    
    func playSound(_ soundName: String) {
        guard !isMuted else { return }
        
        // Placeholder for sound playing logic
        // In a real implementation, you would load and play audio files here
        print("Playing sound: \(soundName)")
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
}
