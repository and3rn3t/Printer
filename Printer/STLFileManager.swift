//
//  STLFileManager.swift
//  Printer
//
//  Created by Matt on 2/10/26.
//

import Foundation
import UniformTypeIdentifiers

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
        let destinationURL = try await stlDirectory
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
    
    /// Save STL data and return the file URL and size
    func saveSTL(data: Data, filename: String) async throws -> (url: URL, size: Int64) {
        let url = try await stlDirectory.appendingPathComponent(filename)
        let uniqueURL = try makeUniqueURL(url)
        
        try data.write(to: uniqueURL)
        
        return (uniqueURL, Int64(data.count))
    }
    
    /// Read STL file data
    func readSTL(at path: String) async throws -> Data {
        let url = URL(fileURLWithPath: path)
        return try Data(contentsOf: url)
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
    
    /// Validate STL file format (basic check)
    func validateSTL(data: Data) -> Bool {
        // Check if binary STL (starts with 80 bytes header, then 4 bytes for triangle count)
        if data.count > 84 {
            // Binary STL
            return true
        }
        
        // Check if ASCII STL (starts with "solid")
        if let string = String(data: data.prefix(5), encoding: .ascii),
           string.lowercased() == "solid" {
            return true
        }
        
        return false
    }
}

extension UTType {
    static var stl: UTType {
        UTType(filenameExtension: "stl") ?? .data
    }
}
