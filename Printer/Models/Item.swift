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
    
    /// Relative path to the STL file within the documents directory
    /// Stored as a relative path (e.g. "STLFiles/model.stl") so it survives container changes
    var fileURL: String
    
    /// Resolves the stored relative path to an absolute URL
    var resolvedFileURL: URL {
        let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        return documentsDirectory.appendingPathComponent(fileURL)
    }
    
    /// Size in bytes
    var fileSize: Int64
    
    /// Source of the model
    var source: ModelSource
    
    /// Thumbnail image data (optional, stored externally for performance)
    @Attribute(.externalStorage) var thumbnailData: Data?
    
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

    /// Name of the file being printed
    var fileName: String?

    /// IP address of the printer used
    var printerIP: String?

    /// Protocol used for this job
    var jobProtocol: String?

    /// Total elapsed print time in seconds (accumulated across pause/resume)
    var elapsedTime: TimeInterval

    /// Timestamp when the print actually started on the printer (vs. when the job record was created)
    var printStartDate: Date?

    /// Duration of the print in a human-readable format
    var formattedDuration: String {
        let seconds = effectiveDuration
        guard seconds > 0 else { return "—" }
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(secs)s"
        }
        return "\(secs)s"
    }

    /// Best available duration: stored elapsed time, or calculated from start/end dates
    var effectiveDuration: TimeInterval {
        if elapsedTime > 0 {
            return elapsedTime
        }
        guard let end = endDate else {
            // Still running — compute from start
            let start = printStartDate ?? startDate
            return Date().timeIntervalSince(start)
        }
        let start = printStartDate ?? startDate
        return end.timeIntervalSince(start)
    }

    init(
        printerName: String,
        status: PrintStatus = .preparing,
        fileName: String? = nil,
        printerIP: String? = nil,
        jobProtocol: String? = nil
    ) {
        self.id = UUID()
        self.startDate = Date()
        self.status = status
        self.printerName = printerName
        self.fileName = fileName
        self.printerIP = printerIP
        self.jobProtocol = jobProtocol
        self.elapsedTime = 0
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

/// Communication protocol used by a printer
///
/// - `act`: Anycubic TCP protocol (Photon resin printers, port 6000)
/// - `octoprint`: OctoPrint-compatible REST API (FDM printers, port 80)
/// - `anycubicHTTP`: Anycubic native HTTP API (port 18910)
enum PrinterProtocol: String, Codable {
    case act
    case octoprint
    case anycubicHTTP
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
    
    /// Serial number / CN from Anycubic discovery
    var serialNumber: String?
    
    /// Port used for connection (default 6000 for ACT, 80 for OctoPrint, 18910 for Anycubic HTTP)
    var port: Int
    
    /// Communication protocol — ACT for Photon resin printers, OctoPrint for FDM
    var printerProtocol: PrinterProtocol
    
    /// Device ID for MQTT communication
    var deviceId: String?
    
    /// Mode ID for MQTT communication
    var modeId: String?
    
    /// Firmware version reported by printer
    var firmwareVersion: String?
    
    init(
        name: String,
        ipAddress: String,
        apiKey: String? = nil,
        manufacturer: String = "Anycubic",
        model: String = "",
        port: Int = 6000,
        printerProtocol: PrinterProtocol = .act
    ) {
        self.id = UUID()
        self.name = name
        self.ipAddress = ipAddress
        self.apiKey = apiKey
        self.manufacturer = manufacturer
        self.model = model
        self.port = port
        self.printerProtocol = printerProtocol
        self.isConnected = false
    }
}

