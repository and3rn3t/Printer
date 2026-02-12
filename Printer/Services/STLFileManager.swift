//
//  STLFileManager.swift
//  Printer
//
//  Created by Matt on 2/10/26.
//

import Foundation
import UniformTypeIdentifiers
import OSLog

/// Manages STL file operations including import, export, and storage
actor STLFileManager {

    static let shared = STLFileManager()

    private let fileManager = FileManager.default

    /// Directory for storing STL files
    private var stlDirectory: URL {
        get throws {
            let documentsDirectory = try fileManager.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let stlDir = documentsDirectory.appendingPathComponent("STLFiles", isDirectory: true)

            if !fileManager.fileExists(atPath: stlDir.path) {
                try fileManager.createDirectory(at: stlDir, withIntermediateDirectories: true)
            }

            return stlDir
        }
    }

    /// Import an STL file from a URL
    func importSTL(from sourceURL: URL) async throws -> (url: URL, size: Int64) {
        let destinationURL = try stlDirectory
            .appendingPathComponent(sourceURL.lastPathComponent)

        // If file exists, make it unique
        let uniqueURL = try makeUniqueURL(destinationURL)

        // Copy the file
        try fileManager.copyItem(at: sourceURL, to: uniqueURL)

        // Get file size
        let attributes = try fileManager.attributesOfItem(atPath: uniqueURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0

        return (uniqueURL, fileSize)
    }

    /// Delete an STL file
    func deleteSTL(at path: String) async throws {
        let url = URL(fileURLWithPath: path)
        try fileManager.removeItem(at: url)
    }

    /// Check if STL file exists
    func fileExists(at path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    /// Create a unique filename if one already exists
    private func makeUniqueURL(_ url: URL) throws -> URL {
        var uniqueURL = url
        var counter = 1

        while fileManager.fileExists(atPath: uniqueURL.path) {
            let filename = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            uniqueURL = url.deletingLastPathComponent()
                .appendingPathComponent("\(filename)_\(counter)")
                .appendingPathExtension(ext)
            counter += 1
        }

        return uniqueURL
    }

    /// Convert an absolute file URL to a relative path (relative to Documents directory)
    /// for stable storage in SwiftData
    func relativePath(for url: URL) -> String {
        let documentsDirectory = try? fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        guard let documentsPath = documentsDirectory?.path else {
            return url.lastPathComponent
        }
        let fullPath = url.path
        if fullPath.hasPrefix(documentsPath) {
            // Strip the documents directory prefix and leading slash
            let relative = String(fullPath.dropFirst(documentsPath.count))
            return relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
        }
        return url.lastPathComponent
    }

}

extension UTType {
    static var stl: UTType {
        UTType(filenameExtension: "stl") ?? .data
    }

    static var obj: UTType {
        UTType(filenameExtension: "obj") ?? .threeDContent
    }

    static var usdz: UTType {
        UTType(filenameExtension: "usdz") ?? .usdz
    }

    static var threeMF: UTType {
        UTType(filenameExtension: "3mf") ?? .data
    }

    static var gcode: UTType {
        UTType(filenameExtension: "gcode") ?? .data
    }

    static var pwmx: UTType {
        UTType(filenameExtension: "pwmx") ?? .data
    }

    static var ctb: UTType {
        UTType(filenameExtension: "ctb") ?? .data
    }
}
