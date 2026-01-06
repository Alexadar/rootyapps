#if !os(macOS)
import SwiftUI
import AVKit
import AVFoundation
import UIKit

/// UIViewRepresentable wrapper for AVPlayer on iOS
struct VideoPlayerPlatformView: UIViewRepresentable {
    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.setupPlayer()
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerUIView, coordinator: ()) {
        uiView.cleanup()
    }
}

class PlayerUIView: UIView {
    private let videos = ["spaceship_vid", "shuttle_vid"]
    private var currentIndex = 0

    private var currentPlayer: AVPlayer?
    private var currentLayer: AVPlayerLayer?

    private var observer: NSObjectProtocol?
    private let fadeDuration: TimeInterval = 0.2
    private let videoVolume: Float = 0.0 // Video muted

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
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

        let playerLayer = AVPlayerLayer(player: newPlayer)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = bounds
        playerLayer.opacity = 0.0

        layer.addSublayer(playerLayer)

        observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.transitionToNextVideo()
        }

        currentPlayer = newPlayer
        currentLayer = playerLayer

        // Fade in from black
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0.0
        fadeIn.toValue = 1.0
        fadeIn.duration = fadeDuration
        fadeIn.timingFunction = CAMediaTimingFunction(name: .linear)
        fadeIn.fillMode = .forwards
        fadeIn.isRemovedOnCompletion = false

        playerLayer.add(fadeIn, forKey: "fadeIn")
        playerLayer.opacity = 1.0

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

    override func layoutSubviews() {
        super.layoutSubviews()
        currentLayer?.frame = bounds
    }
}
#endif
