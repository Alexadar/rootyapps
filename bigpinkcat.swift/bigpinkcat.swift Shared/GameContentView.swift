//
//  GameContentView.swift
//  bigpinkcat.swift
//
//  SwiftUI view that hosts the SpriteKit VisualNovelScene
//

import SwiftUI
import SpriteKit

#if os(macOS)
// macOS version - windowed with specific default size
struct GameContentView: View {
    @State private var scene: SKScene = makeScene()

    var body: some View {
        GeometryReader { geometry in
            SpriteView(scene: scene, preferredFramesPerSecond: 60, options: [.allowsTransparency])
                .ignoresSafeArea()
                .onChange(of: geometry.size) { oldSize, newSize in
                    // Scene handles resize via didChangeSize
                }
        }
    }
}

private func makeScene() -> SKScene {
    let sceneSize = CGSize(width: 1920, height: 1080)
    let scene = VisualNovelScene(size: sceneSize)
    scene.scaleMode = .resizeFill
    return scene
}

#else
// iOS/tvOS/visionOS version - fullscreen optimized
struct GameContentView: View {
    @State private var scene: SKScene?

    var body: some View {
        GeometryReader { geometry in
            if let scene = scene {
                SpriteView(scene: scene, preferredFramesPerSecond: 60, options: [.allowsTransparency, .ignoresSiblingOrder])
                    .ignoresSafeArea(.all)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                Color.black
                    .ignoresSafeArea(.all)
                    .onAppear {
                        // Create scene with actual screen size for better fullscreen
                        let sceneSize = geometry.size
                        let newScene = VisualNovelScene(size: sceneSize)
                        newScene.scaleMode = .resizeFill
                        scene = newScene
                    }
            }
        }
        #if os(iOS)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #endif
    }
}
#endif

#if DEBUG
#Preview {
    GameContentView()
}
#endif
