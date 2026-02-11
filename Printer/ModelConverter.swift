//
//  ModelConverter.swift
//  Printer
//
//  Created by Matt on 2/10/26.
//

import Foundation
import ModelIO
import SceneKit

/// Converts between different 3D model formats
actor ModelConverter {
    
    enum ConversionError: LocalizedError {
        case unsupportedFormat
        case conversionFailed
        case fileNotFound
        
        var errorDescription: String? {
            switch self {
            case .unsupportedFormat:
                return "Unsupported file format"
            case .conversionFailed:
                return "Model conversion failed"
            case .fileNotFound:
                return "Source file not found"
            }
        }
    }
    
    /// Convert USDZ to STL format
    func convertUSDZToSTL(usdzURL: URL) async throws -> URL {
        guard FileManager.default.fileExists(atPath: usdzURL.path) else {
            throw ConversionError.fileNotFound
        }
        
        // Load the USDZ file using ModelIO
        let asset = MDLAsset(url: usdzURL)
        
        // Get all meshes from the asset
        guard asset.count > 0 else {
            throw ConversionError.conversionFailed
        }
        
        // Create output URL
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(usdzURL.deletingPathExtension().lastPathComponent + ".stl")
        
        // Export as STL
        // ModelIO can export to STL format
        try asset.export(to: outputURL)
        
        return outputURL
    }
    
    /// Convert OBJ to STL format
    func convertOBJToSTL(objURL: URL) async throws -> URL {
        guard FileManager.default.fileExists(atPath: objURL.path) else {
            throw ConversionError.fileNotFound
        }
        
        let asset = MDLAsset(url: objURL)
        
        guard asset.count > 0 else {
            throw ConversionError.conversionFailed
        }
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(objURL.deletingPathExtension().lastPathComponent + ".stl")
        
        try asset.export(to: outputURL)
        
        return outputURL
    }
    
    /// Generate thumbnail from 3D model
    func generateThumbnail(from modelURL: URL, size: CGSize = CGSize(width: 200, height: 200)) async throws -> Data? {
        return await withCheckedContinuation { continuation in
            // Create a SCNScene from the model
            let scene: SCNScene
            
            if modelURL.pathExtension.lowercased() == "usdz" {
                guard let loadedScene = try? SCNScene(url: modelURL, options: nil) else {
                    continuation.resume(returning: nil)
                    return
                }
                scene = loadedScene
            } else if modelURL.pathExtension.lowercased() == "stl" {
                // Load STL using ModelIO
                let asset = MDLAsset(url: modelURL)
                scene = SCNScene()
                
                for object in asset.childObjects(of: MDLObject.self) {
                    let node = SCNNode(mdlObject: object)
                    scene.rootNode.addChildNode(node)
                }
            } else {
                continuation.resume(returning: nil)
                return
            }
            
            // Setup renderer
            let renderer = SCNRenderer(device: nil, options: nil)
            renderer.scene = scene
            
            // Add camera
            let cameraNode = SCNNode()
            cameraNode.camera = SCNCamera()
            cameraNode.position = SCNVector3(x: 0, y: 0, z: 5)
            scene.rootNode.addChildNode(cameraNode)
            
            // Add light
            let lightNode = SCNNode()
            lightNode.light = SCNLight()
            lightNode.light?.type = .omni
            lightNode.position = SCNVector3(x: 0, y: 10, z: 10)
            scene.rootNode.addChildNode(lightNode)
            
            // Render to image
            #if os(macOS)
            let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
            let data = image.tiffRepresentation
            continuation.resume(returning: data)
            #else
            let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
            let data = image.pngData()
            continuation.resume(returning: data)
            #endif
        }
    }
}
