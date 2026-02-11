//
//  MeshAnalyzer.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import Foundation
import ModelIO
import SceneKit
import SceneKit.ModelIO

/// Analyzes 3D mesh files to extract bounding-box dimensions, vertex counts, and triangle counts.
///
/// Uses ModelIO to load STL/OBJ/USDZ assets and compute spatial information.
actor MeshAnalyzer {

    /// Result of a mesh analysis
    struct MeshInfo: Sendable {
        /// Width (X) in millimeters
        let dimensionX: Float
        /// Depth (Y) in millimeters
        let dimensionY: Float
        /// Height (Z) in millimeters
        let dimensionZ: Float
        /// Total number of vertices across all meshes
        let vertexCount: Int
        /// Total number of triangles (faces) across all meshes
        let triangleCount: Int
    }

    enum AnalysisError: LocalizedError {
        case fileNotFound
        case unsupportedFormat
        case noMeshData

        var errorDescription: String? {
            switch self {
            case .fileNotFound: return "File not found"
            case .unsupportedFormat: return "Unsupported file format for mesh analysis"
            case .noMeshData: return "No mesh data found in file"
            }
        }
    }

    /// Analyze a 3D model file and extract dimensional / mesh information.
    ///
    /// - Parameter url: URL to an STL, OBJ, or USDZ file
    /// - Returns: `MeshInfo` with bounding-box dimensions and mesh statistics
    func analyze(url: URL) throws -> MeshInfo {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AnalysisError.fileNotFound
        }

        let ext = url.pathExtension.lowercased()
        guard ["stl", "obj", "usdz", "usda", "usdc", "3mf"].contains(ext) else {
            throw AnalysisError.unsupportedFormat
        }

        let asset = MDLAsset(url: url)
        asset.loadTextures()

        let bbox = asset.boundingBox
        let minBounds = bbox.minBounds
        let maxBounds = bbox.maxBounds

        let dimX = maxBounds.x - minBounds.x
        let dimY = maxBounds.y - minBounds.y
        let dimZ = maxBounds.z - minBounds.z

        // Count vertices and triangles across all meshes in the asset
        var totalVertices = 0
        var totalTriangles = 0

        for i in 0..<asset.count {
            guard let object = asset.object(at: i) as? MDLMesh else { continue }
            totalVertices += object.vertexCount

            for submesh in object.submeshes as? [MDLSubmesh] ?? [] {
                let indexCount = submesh.indexCount
                switch submesh.geometryType {
                case .triangles:
                    totalTriangles += indexCount / 3
                case .triangleStrips:
                    totalTriangles += max(0, indexCount - 2)
                default:
                    // Approximate for other geometry types
                    totalTriangles += indexCount / 3
                }
            }
        }

        // Also recurse into child objects
        func countMeshes(in object: MDLObject) {
            if let mesh = object as? MDLMesh {
                totalVertices += mesh.vertexCount
                for submesh in mesh.submeshes as? [MDLSubmesh] ?? [] {
                    let indexCount = submesh.indexCount
                    switch submesh.geometryType {
                    case .triangles:
                        totalTriangles += indexCount / 3
                    case .triangleStrips:
                        totalTriangles += max(0, indexCount - 2)
                    default:
                        totalTriangles += indexCount / 3
                    }
                }
            }
            for childIdx in 0..<object.children.count {
                countMeshes(in: object.children[childIdx])
            }
        }

        // If top-level objects weren't MDLMesh, drill into the hierarchy
        if totalVertices == 0 {
            for i in 0..<asset.count {
                let obj = asset.object(at: i)
                countMeshes(in: obj)
            }
        }

        guard dimX > 0 || dimY > 0 || dimZ > 0 else {
            throw AnalysisError.noMeshData
        }

        return MeshInfo(
            dimensionX: dimX,
            dimensionY: dimY,
            dimensionZ: dimZ,
            vertexCount: totalVertices,
            triangleCount: totalTriangles
        )
    }
}
