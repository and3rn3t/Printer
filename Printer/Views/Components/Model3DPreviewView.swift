//
//  Model3DPreviewView.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import SwiftUI
import SceneKit
import SceneKit.ModelIO
import ModelIO

/// Interactive 3D model preview using SceneKit.
///
/// Supports STL, OBJ, and USDZ files with orbit camera controls (rotate, zoom, pan).
/// Automatically centers and scales the model to fit the viewport.
struct Model3DPreviewView: View {
    let fileURL: URL
    let fileType: ModelFileType

    @State private var scene: SCNScene?
    @State private var loadError: String?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView("Loading 3D Model…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.gray.opacity(0.05))
            } else if let scene {
                SceneKitContainer(scene: scene)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else if let loadError {
                ContentUnavailableView {
                    Label("Preview Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                }
            }
        }
        .task {
            await loadScene()
        }
    }

    // MARK: - Scene Loading

    @MainActor
    private func loadScene() async {
        isLoading = true
        defer { isLoading = false }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            loadError = "Model file not found"
            return
        }

        // Only mesh formats can be previewed in 3D
        guard fileType.needsSlicing || fileType == .unknown else {
            loadError = "3D preview is only available for mesh formats (STL, OBJ, USDZ)"
            return
        }

        do {
            let loaded: SCNScene
            let ext = fileURL.pathExtension.lowercased()

            if ext == "usdz" || ext == "usda" || ext == "usdc" {
                guard let s = try? SCNScene(url: fileURL, options: nil) else {
                    loadError = "Failed to load USDZ scene"
                    return
                }
                loaded = s
            } else {
                // STL, OBJ — load via ModelIO
                let asset = MDLAsset(url: fileURL)
                asset.loadTextures()
                loaded = SCNScene(mdlAsset: asset)
            }

            // Setup scene environment
            setupScene(loaded)
            scene = loaded
        }
    }

    /// Configure lighting, camera, and auto-fit the model
    @MainActor
    private func setupScene(_ scene: SCNScene) {
        // Calculate bounding box to auto-center
        let (minVec, maxVec) = scene.rootNode.boundingBox
        let center = SCNVector3(
            (minVec.x + maxVec.x) / 2,
            (minVec.y + maxVec.y) / 2,
            (minVec.z + maxVec.z) / 2
        )
        let size = SCNVector3(
            maxVec.x - minVec.x,
            maxVec.y - minVec.y,
            maxVec.z - minVec.z
        )
        let maxDimension = max(size.x, max(size.y, size.z))
        guard maxDimension > 0 else { return }

        // Center the model at origin
        let pivotNode = SCNNode()
        for child in scene.rootNode.childNodes {
            pivotNode.addChildNode(child)
        }
        pivotNode.position = SCNVector3(-center.x, -center.y, -center.z)

        let containerNode = SCNNode()
        containerNode.addChildNode(pivotNode)
        scene.rootNode.addChildNode(containerNode)

        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.automaticallyAdjustsZRange = true
        let cameraDistance = Float(maxDimension) * 2.0
        cameraNode.position = SCNVector3(0, Float(maxDimension) * 0.3, cameraDistance)
        cameraNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(cameraNode)

        // Ambient light
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 400
        ambientLight.light?.color = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        scene.rootNode.addChildNode(ambientLight)

        // Directional light (key)
        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light?.type = .directional
        keyLight.light?.intensity = 800
        keyLight.light?.castsShadow = true
        keyLight.position = SCNVector3(cameraDistance, cameraDistance, cameraDistance)
        keyLight.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(keyLight)

        // Fill light
        let fillLight = SCNNode()
        fillLight.light = SCNLight()
        fillLight.light?.type = .directional
        fillLight.light?.intensity = 300
        fillLight.position = SCNVector3(-cameraDistance, cameraDistance * 0.5, -cameraDistance * 0.5)
        fillLight.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(fillLight)

        // Set a default material if none exists (common for STL files)
        scene.rootNode.enumerateChildNodes { node, _ in
            if let geometry = node.geometry {
                for material in geometry.materials where material.diffuse.contents == nil {
                    material.diffuse.contents = CGColor(red: 0.6, green: 0.65, blue: 0.75, alpha: 1.0)
                    material.specular.contents = CGColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
                    material.shininess = 0.3
                    material.lightingModel = .physicallyBased
                    material.metalness.contents = 0.1
                    material.roughness.contents = 0.6
                }
            }
        }

        // Floor grid (optional subtle reference)
        let floor = SCNFloor()
        floor.reflectivity = 0.05
        floor.firstMaterial?.diffuse.contents = CGColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1.0)
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(0, minVec.y - center.y, 0)
        scene.rootNode.addChildNode(floorNode)

        // Scene background
        scene.background.contents = CGColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0)
    }
}

// MARK: - SceneKit UIViewRepresentable / NSViewRepresentable

#if os(macOS)
struct SceneKitContainer: NSViewRepresentable {
    let scene: SCNScene

    func makeNSView(context: Context) -> SCNView {
        createSCNView()
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        nsView.scene = scene
    }
}
#else
struct SceneKitContainer: UIViewRepresentable {
    let scene: SCNScene

    func makeUIView(context: Context) -> SCNView {
        createSCNView()
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.scene = scene
    }
}
#endif

extension SceneKitContainer {
    func createSCNView() -> SCNView {
        let scnView = SCNView()
        scnView.scene = scene
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.antialiasingMode = .multisampling4X
        scnView.backgroundColor = .clear
        scnView.preferredFramesPerSecond = 60
        return scnView
    }
}
