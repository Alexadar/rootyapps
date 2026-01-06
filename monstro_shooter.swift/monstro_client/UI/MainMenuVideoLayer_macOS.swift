#if os(macOS)
import SwiftUI
import AVKit
import AVFoundation
import AppKit

/// NSViewRepresentable wrapper for AVPlayer on macOS
///
/// IMPORTANT: Uses NSViewRepresentable instead of SwiftUI's VideoPlayer to avoid
/// "Simultaneous accesses to memory, but modification requires exclusive access" crash.
/// SwiftUI's VideoPlayer with @State/@StateObject causes race conditions when the player
/// updates during SwiftUI's view rendering cycle. NSView-based approach isolates the player
/// from SwiftUI's state system entirely.
struct VideoPlayerPlatformView: NSViewRepresentable {
    func makeNSView(context: Context) -> PlayerNSView {
        let view = PlayerNSView()
        view.setupPlayer()
        return view
    }

    func updateNSView(_ nsView: PlayerNSView, context: Context) {}

    static func dismantleNSView(_ nsView: PlayerNSView, coordinator: ()) {
        nsView.cleanup()
    }
}

class PlayerNSView: NSView {
    private let videos = ["spaceship_vid", "shuttle_vid"]
    private var currentIndex = 0

    private var currentPlayer: AVPlayer?
    private var currentLayer: AVPlayerLayer?

    private var observer: NSObjectProtocol?
    private let fadeDuration: TimeInterval = 0.2
    private let videoVolume: Float = 0.0 // Video muted

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        self.layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    func setupPlayer() {
        loadVideo(at: currentIndex)
    }

    private func loadVideo(at index: Int) {
        let videoName = videos[index]

        guard let path = Bundle.main.path(forResource: videoName, ofType: "mp4") else {
            print("[VideoPlayer] Error: Could not find \(videoName).mp4")
            return
        }

        let url = URL(fileURLWithPath: path)
        let playerItem = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.volume = videoVolume

        let layer = AVPlayerLayer(player: newPlayer)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer.opacity = 0.0

        self.layer?.addSublayer(layer)

        observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.transitionToNextVideo()
        }

        currentPlayer = newPlayer
        currentLayer = layer

        // Fade in from black
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0.0
        fadeIn.toValue = 1.0
        fadeIn.duration = fadeDuration
        fadeIn.timingFunction = CAMediaTimingFunction(name: .linear)
        fadeIn.fillMode = .forwards
        fadeIn.isRemovedOnCompletion = false

        layer.add(fadeIn, forKey: "fadeIn")
        layer.opacity = 1.0

        newPlayer.play()
    }

    private func transitionToNextVideo() {
        guard let oldPlayer = currentPlayer, let oldLayer = currentLayer else {
            return
        }

        // Fade out to black
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1.0
        fadeOut.toValue = 0.0
        fadeOut.duration = fadeDuration
        fadeOut.timingFunction = CAMediaTimingFunction(name: .linear)
        fadeOut.fillMode = .forwards
        fadeOut.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            oldPlayer.pause()
            oldLayer.removeFromSuperlayer()

            // Remove old observer
            if let observer = self?.observer {
                NotificationCenter.default.removeObserver(observer)
                self?.observer = nil
            }

            // Load next video after fade to black completes
            let nextIndex = ((self?.currentIndex ?? 0) + 1) % (self?.videos.count ?? 1)
            self?.currentIndex = nextIndex
            self?.loadVideo(at: nextIndex)
        }

        oldLayer.add(fadeOut, forKey: "fadeOut")
        oldLayer.opacity = 0.0

        CATransaction.commit()
    }

    func cleanup() {
        currentPlayer?.pause()
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
        currentLayer?.removeFromSuperlayer()
        currentPlayer = nil
        currentLayer = nil
    }

    deinit {
        cleanup()
    }

    override func layout() {
        super.layout()
        currentLayer?.frame = bounds
    }
}
#endif
