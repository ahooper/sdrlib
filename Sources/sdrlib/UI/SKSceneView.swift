//
//  SKSceneView.swift
//  sdrplay1
//
//  Created by Andy Hooper on 2023-04-10.
//

// https://www.hackingwithswift.com/forums/swiftui/swiftui-spritekit-macos-catalina-10-15/2662/2669

import SwiftUI
import SpriteKit

struct SKSceneView: View {
    let scene: SKScene

    var body: some View {
        GeometryReader { proxy in
            SKSceneViewRepresentable(scene: scene, proxy: proxy)
        }
    }
}

struct SKSceneViewRepresentable: NSViewRepresentable {
    let scene: SKScene
    let proxy: GeometryProxy

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SKView {
        scene.size = proxy.size
        context.coordinator.scene = scene

        let view = SKView()
        view.presentScene(scene)
        return view
    }

    func updateNSView(_ nsView: SKView, context: Context) {
        context.coordinator.resizeScene(proxy: proxy)
    }

    class Coordinator: NSObject {
        weak var scene: SKScene?

        func resizeScene(proxy: GeometryProxy) {
            scene?.size = proxy.size
        }
    }
}
