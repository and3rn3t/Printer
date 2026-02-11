//
//  Item.swift
//  Printer
//
//  Created by Matt on 2/10/26.
//

import Foundation
import SwiftData

/// Represents a 3D model that can be printed
@Model
final class PrintModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdDate: Date
    var modifiedDate: Date
    
    /// Path to the STL file in documents directory
    var fileURL: String
    
    /// Size in bytes
    var fileSize: Int64
    
    /// Source of the model
    var source: ModelSource
    
    /// Thumbnail image data (optional)
    var thumbnailData: Data?
    
    /// Notes about the model
    var notes: String
    
    /// Print history
    @Relationship(deleteRule: .cascade)
    var printJobs: [PrintJob]
    
    init(
        name: String,
        fileURL: String,
        fileSize: Int64,
        source: ModelSource,
        thumbnailData: Data? = nil,
        notes: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.createdDate = Date()
        self.modifiedDate = Date()
        self.fileURL = fileURL
        self.fileSize = fileSize
        self.source = source
        self.thumbnailData = thumbnailData
        self.notes = notes
        self.printJobs = []
    }
}
enum ModelSource: Codable {
    case scanned
    case imported
    case downloaded
}

/// Represents a print job sent to a printer
@Model
final class PrintJob {
    @Attribute(.unique) var id: UUID
    var startDate: Date
    var endDate: Date?
    var status: PrintStatus
    var printerName: String
    var model: PrintModel?
    
    init(
        printerName: String,
        status: PrintStatus = .preparing
    ) {
        self.id = UUID()
        self.startDate = Date()
        self.status = status
        self.printerName = printerName
    }
}

enum PrintStatus: Codable {
    case preparing
    case uploading
    case queued
    case printing
    case completed
    case failed
    case cancelled
}

/// Represents a connected 3D printer
@Model
final class Printer {
    @Attribute(.unique) var id: UUID
    var name: String
    var ipAddress: String
    var apiKey: String?
    var manufacturer: String
    var model: String
    var lastConnected: Date?
    var isConnected: Bool
    
    init(
        name: String,
        ipAddress: String,
        apiKey: String? = nil,
        manufacturer: String = "Anycubic",
        model: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.ipAddress = ipAddress
        self.apiKey = apiKey
        self.manufacturer = manufacturer
        self.model = model
        self.isConnected = false
    }
}

