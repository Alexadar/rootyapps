//
//  GameContentView.swift
//  bigpinkcat.swift
//
//  SwiftUI view that hosts the SpriteKit VisualNovelScene
//

import SwiftUI
import SpriteKit

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
        #if os(iOS)
        .statusBarHidden()
        #endif
    }
}

private func makeScene() -> SKScene {
    let sceneSize = CGSize(width: 1920, height: 1080)
    let scene = VisualNovelScene(size: sceneSize)
    scene.scaleMode = .resizeFill
    return scene
}

#if DEBUG
#Preview {
    GameContentView()
}
#endif
