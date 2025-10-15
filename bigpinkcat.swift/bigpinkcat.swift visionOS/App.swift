//
//  App.swift
//  bigpinkcat.swift visionOS
//
//  Minimal visionOS entry that hosts the existing SpriteKit VisualNovelScene
//

import SwiftUI
import SpriteKit

private func makeScene() -> SKScene {
    // Start with an HD canvas; we resize to fit the window
    let sceneSize = CGSize(width: 1920, height: 1080)
    let scene = VisualNovelScene(size: sceneSize)
    scene.scaleMode = .resizeFill
    return scene
}

struct VisualNovelRootView: View {
    @State private var scene = makeScene()

    var body: some View {
        SpriteView(scene: scene, preferredFramesPerSecond: 60, options: [.allowsTransparency])
            .ignoresSafeArea()
            .onAppear {
                // Any additional startup needed for visionOS can go here
            }
    }
}

@main
struct BigPinkCatVisionApp: App {
    var body: some Scene {
        WindowGroup {
            VisualNovelRootView()
        }
    }
}
