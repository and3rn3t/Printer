//
//  CloudSyncManager.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import Foundation
import SwiftData

/// Manages iCloud file synchronization for 3D model files.
///
/// SwiftData handles metadata sync via CloudKit automatically when the
/// `ModelConfiguration` uses `.automatic` cloud database. This actor handles
/// the complementary task of syncing the actual model files (STL, PWMX, etc.)
/// via the iCloud ubiquity container.
actor CloudSyncManager {
    static let shared = CloudSyncManager()

    /// Whether iCloud is available for the current user
    var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// iCloud Documents container URL (if available)
    var iCloudDocumentsURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents", isDirectory: true)
    }

    /// Upload a local model file to iCloud Documents
    ///
    /// - Parameters:
    ///   - localURL: URL to the local file in the app's Documents directory
    ///   - relativePath: Relative path (e.g. "STLFiles/model.stl") for iCloud organization
    /// - Returns: True if upload was initiated successfully
    @discardableResult
    func uploadToICloud(localURL: URL, relativePath: String) -> Bool {
        guard let iCloudBase = iCloudDocumentsURL else { return false }

        let iCloudURL = iCloudBase.appendingPathComponent(relativePath)
        let iCloudDir = iCloudURL.deletingLastPathComponent()

        do {
            // Ensure directory exists
            if !FileManager.default.fileExists(atPath: iCloudDir.path) {
                try FileManager.default.createDirectory(at: iCloudDir, withIntermediateDirectories: true)
            }

            // Copy or replace
            if FileManager.default.fileExists(atPath: iCloudURL.path) {
                try FileManager.default.removeItem(at: iCloudURL)
            }
            try FileManager.default.copyItem(at: localURL, to: iCloudURL)
            return true
        } catch {
            return false
        }
    }

    /// Download a file from iCloud Documents to local storage if it doesn't exist locally.
    ///
    /// - Parameters:
    ///   - relativePath: Relative path of the file
    ///   - localDocumentsURL: The app's local Documents directory
    /// - Returns: True if file exists locally after this call
    func ensureLocalCopy(relativePath: String, localDocumentsURL: URL) async -> Bool {
        let localURL = localDocumentsURL.appendingPathComponent(relativePath)

        // Already exists locally
        if FileManager.default.fileExists(atPath: localURL.path) {
            return true
        }

        // Check iCloud
        guard let iCloudBase = iCloudDocumentsURL else { return false }
        let iCloudURL = iCloudBase.appendingPathComponent(relativePath)

        // Start downloading if it's in iCloud
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: iCloudURL)

            // Wait for download (with timeout)
            for _ in 0..<30 {
                if FileManager.default.fileExists(atPath: iCloudURL.path) {
                    let localDir = localURL.deletingLastPathComponent()
                    if !FileManager.default.fileExists(atPath: localDir.path) {
                        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
                    }
                    try FileManager.default.copyItem(at: iCloudURL, to: localURL)
                    return true
                }
                try await Task.sleep(for: .seconds(1))
            }
        } catch {
            return false
        }

        return false
    }

    /// Sync status for display in settings
    struct SyncStatus {
        let isAvailable: Bool
        let fileCount: Int
        let lastSynced: Date?
    }

    /// Get current sync status
    func getSyncStatus() -> SyncStatus {
        let isAvailable = self.isICloudAvailable

        var fileCount = 0
        if let iCloudDocs = iCloudDocumentsURL {
            let stlDir = iCloudDocs.appendingPathComponent("STLFiles")
            if let enumerator = FileManager.default.enumerator(at: stlDir, includingPropertiesForKeys: nil) {
                for case _ as URL in enumerator {
                    fileCount += 1
                }
            }
        }

        return SyncStatus(
            isAvailable: isAvailable,
            fileCount: fileCount,
            lastSynced: isAvailable ? Date() : nil
        )
    }
}
