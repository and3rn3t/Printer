//
//  Item.swift
//  Printer
//
//  Created by Matt on 2/10/26.
//

import Foundation
import SwiftData

// MARK: - File Type

/// Recognized 3D file formats
enum ModelFileType: String, Codable, CaseIterable {
    case stl
    case obj
    case usdz
    case pwmx   // Anycubic Photon sliced (resin)
    case pwma   // Anycubic Photon sliced (resin)
    case ctb    // ChiTuBox sliced
    case gcode  // FDM sliced
    case threeMF = "3mf"
    case unknown

    /// Whether this format is a raw mesh that needs slicing before printing
    var needsSlicing: Bool {
        switch self {
        case .stl, .obj, .usdz, .threeMF: return true
        case .pwmx, .pwma, .ctb, .gcode: return false
        case .unknown: return true
        }
    }

    /// Whether this format is a sliced file ready for printing
    var isSliced: Bool { !needsSlicing }

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .stl: return "STL"
        case .obj: return "OBJ"
        case .usdz: return "USDZ"
        case .pwmx: return "PWMX (Anycubic)"
        case .pwma: return "PWMA (Anycubic)"
        case .ctb: return "CTB (ChiTuBox)"
        case .gcode: return "G-code"
        case .threeMF: return "3MF"
        case .unknown: return "Unknown"
        }
    }

    /// Infer file type from a file path or URL
    static func from(path: String) -> ModelFileType {
        let ext = (path as NSString).pathExtension.lowercased()
        return ModelFileType(rawValue: ext) ?? .unknown
    }
}

// MARK: - Sort Option

/// Available sort options for the model library
enum ModelSortOption: String, CaseIterable, Identifiable {
    case dateNewest = "Date (Newest)"
    case dateOldest = "Date (Oldest)"
    case nameAZ = "Name (A-Z)"
    case nameZA = "Name (Z-A)"
    case sizeLargest = "Size (Largest)"
    case sizeSmallest = "Size (Smallest)"
    case printCount = "Most Printed"

    var id: String { rawValue }
}

/// Available filter options for the model library
enum ModelFilterOption: String, CaseIterable, Identifiable {
    case all = "All"
    case scanned = "Scanned"
    case imported = "Imported"
    case downloaded = "Downloaded"
    case favorites = "Favorites"
    case needsSlicing = "Needs Slicing"
    case sliced = "Print Ready"

    var id: String { rawValue }
}

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

    /// Whether the user has favorited this model
    var isFavorite: Bool

    /// User-assigned tags for organization
    var tags: [String]
    
    /// Print history
    @Relationship(deleteRule: .cascade)
    var printJobs: [PrintJob]

    /// Inferred file type based on path extension
    var fileType: ModelFileType {
        ModelFileType.from(path: fileURL)
    }

    /// Whether this model's format needs slicing before it can be printed
    var requiresSlicing: Bool {
        fileType.needsSlicing
    }

    // MARK: - Sliced File Metadata (populated by SlicedFileParser)

    /// Total number of layers in the sliced file
    var slicedLayerCount: Int?
    /// Layer height in millimeters
    var slicedLayerHeight: Float?
    /// Estimated print time in seconds
    var slicedPrintTimeSeconds: Int?
    /// Resin/material volume in milliliters
    var slicedVolumeMl: Float?
    /// Printer X resolution in pixels
    var slicedResolutionX: Int?
    /// Printer Y resolution in pixels
    var slicedResolutionY: Int?
    /// Normal layer exposure time in seconds
    var slicedExposureTime: Float?
    /// Bottom layer exposure time in seconds
    var slicedBottomExposureTime: Float?
    /// Total print height in millimeters
    var slicedPrintHeight: Float?

    /// Whether this model has parsed sliced metadata
    var hasSlicedMetadata: Bool {
        slicedLayerCount != nil
    }

    /// Populate sliced metadata fields from parsed metadata
    func applyMetadata(_ metadata: SlicedFileMetadata) {
        slicedLayerCount = metadata.layerCount > 0 ? Int(metadata.layerCount) : nil
        slicedLayerHeight = metadata.layerHeight > 0 ? metadata.layerHeight : nil
        slicedPrintTimeSeconds = metadata.printTime > 0 ? Int(metadata.printTime) : nil
        slicedVolumeMl = metadata.volumeMl > 0 ? metadata.volumeMl : nil
        slicedResolutionX = metadata.resolutionX > 0 ? Int(metadata.resolutionX) : nil
        slicedResolutionY = metadata.resolutionY > 0 ? Int(metadata.resolutionY) : nil
        slicedExposureTime = metadata.exposureTime > 0 ? metadata.exposureTime : nil
        slicedBottomExposureTime = metadata.bottomExposureTime > 0 ? metadata.bottomExposureTime : nil
        slicedPrintHeight = metadata.printHeight
    }

    init(
        name: String,
        fileURL: String,
        fileSize: Int64,
        source: ModelSource,
        thumbnailData: Data? = nil,
        notes: String = "",
        isFavorite: Bool = false,
        tags: [String] = []
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
        self.isFavorite = isFavorite
        self.tags = tags
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

    /// Position in the print queue (0 = not queued, 1 = next, etc.)
    var queuePosition: Int

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
        jobProtocol: String? = nil,
        queuePosition: Int = 0
    ) {
        self.id = UUID()
        self.startDate = Date()
        self.status = status
        self.printerName = printerName
        self.fileName = fileName
        self.printerIP = printerIP
        self.jobProtocol = jobProtocol
        self.elapsedTime = 0
        self.queuePosition = queuePosition
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

