//
//  Item.swift
//  Printer
//
//  Created by Matt on 2/10/26.
//

import Foundation
import SwiftData
import CoreTransferable
import UniformTypeIdentifiers

// MARK: - File Type

/// Recognized 3D file formats
nonisolated enum ModelFileType: String, Codable, CaseIterable, Sendable {
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
    static func from(path: String) -> Self {
        let ext = (path as NSString).pathExtension.lowercased()
        return Self(rawValue: ext) ?? .unknown
    }
}

// MARK: - Sort Option

/// Available sort options for the model library
enum ModelSortOption: String, CaseIterable, Identifiable, Sendable {
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
enum ModelFilterOption: String, CaseIterable, Identifiable, Sendable {
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
    #Index<PrintModel>([\.modifiedDate], [\.name], [\.isFavorite])

    @Attribute(.unique) var id: UUID
    var name: String
    var createdDate: Date
    var modifiedDate: Date

    /// Relative path to the STL file within the documents directory
    /// Stored as a relative path (e.g. "STLFiles/model.stl") so it survives container changes
    var fileURL: String

    /// Resolves the stored relative path to an absolute URL
    var resolvedFileURL: URL {
        guard let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            fatalError("Documents directory not available")
        }
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

    /// Collections this model belongs to (many-to-many)
    var collections: [ModelCollection]

    /// Inferred file type based on path extension
    var fileType: ModelFileType {
        ModelFileType.from(path: fileURL)
    }

    /// Whether this model's format needs slicing before it can be printed
    var requiresSlicing: Bool {
        fileType.needsSlicing
    }

    // MARK: - Mesh Dimensions (populated by MeshAnalyzer)

    /// Bounding box width in mm
    var dimensionX: Float?
    /// Bounding box depth in mm
    var dimensionY: Float?
    /// Bounding box height in mm
    var dimensionZ: Float?
    /// Total vertex count
    var vertexCount: Int?
    /// Total triangle count
    var triangleCount: Int?

    /// Whether mesh dimensions have been analyzed
    var hasDimensions: Bool {
        dimensionX != nil && dimensionY != nil && dimensionZ != nil
    }

    /// Populate dimension fields from mesh analysis
    func applyMeshInfo(_ info: MeshAnalyzer.MeshInfo) {
        dimensionX = info.dimensionX
        dimensionY = info.dimensionY
        dimensionZ = info.dimensionZ
        vertexCount = info.vertexCount
        triangleCount = info.triangleCount
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
        self.collections = []
    }
}

// MARK: - Transferable

extension PrintModel: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .data) { model in
            SentTransferredFile(model.resolvedFileURL)
        }
    }
}

nonisolated enum ModelSource: Codable, Sendable {
    case scanned
    case imported
    case downloaded
}

/// Represents a print job sent to a printer
@Model
final class PrintJob {
    #Index<PrintJob>([\.startDate], [\.printerName], [\.printerName, \.startDate])

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

    /// Resin/material profile used for this print
    var resinProfile: ResinProfile?

    /// Structured failure reason (only set when status == .failed)
    var failureReason: FailureReason?

    /// Free-text notes about the failure
    var failureNotes: String?

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

nonisolated enum PrintStatus: Codable, Sendable {
    case preparing
    case uploading
    case queued
    case printing
    case completed
    case failed
    case cancelled
}

/// Structured reason for a print failure.
nonisolated enum FailureReason: String, Codable, CaseIterable, Identifiable, Sendable {
    case adhesion = "Bed Adhesion"
    case supportFailure = "Support Failure"
    case fepDamage = "FEP Damage"
    case layerShift = "Layer Shift"
    case resinLeak = "Resin Leak"
    case curing = "Curing Issue"
    case fileCorrupt = "Corrupt File"
    case networkError = "Network Error"
    case printerError = "Printer Error"
    case powerLoss = "Power Loss"
    case userCancelled = "User Cancelled"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .adhesion: return "arrow.down.to.line"
        case .supportFailure: return "building.columns"
        case .fepDamage: return "film"
        case .layerShift: return "arrow.left.arrow.right"
        case .resinLeak: return "drop.triangle"
        case .curing: return "sun.max"
        case .fileCorrupt: return "doc.badge.ellipsis"
        case .networkError: return "wifi.slash"
        case .printerError: return "exclamationmark.triangle"
        case .powerLoss: return "bolt.slash"
        case .userCancelled: return "xmark.circle"
        case .other: return "questionmark.circle"
        }
    }
}

/// Communication protocol used by a printer
///
/// - `act`: Anycubic TCP protocol (Photon resin printers, port 6000)
/// - `octoprint`: OctoPrint-compatible REST API (FDM printers, port 80)
/// - `anycubicHTTP`: Anycubic native HTTP API (port 18910)
nonisolated enum PrinterProtocol: String, Codable, Sendable {
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

    /// Maintenance events logged for this printer
    @Relationship(deleteRule: .cascade, inverse: \MaintenanceEvent.printer)
    var maintenanceEvents: [MaintenanceEvent]

    /// Resin cost per milliliter for this printer (overrides global setting)
    var resinCostPerMl: Double?

    /// Build plate width in mm
    var buildPlateX: Float?
    /// Build plate depth in mm
    var buildPlateY: Float?
    /// Build plate max height in mm
    var buildPlateZ: Float?

    /// Well-known build plate specs from printer model name.
    /// Returns (width, depth, height) in mm, or nil if unknown.
    static func knownBuildPlate(for model: String) -> (Float, Float, Float)? {
        let m = model.lowercased()
        if m.contains("mono x 6k") || m.contains("mono x 6ks") { return (198, 122, 245) }
        if m.contains("mono x2") { return (196, 122, 200) }
        if m.contains("mono x") { return (192, 120, 245) }
        if m.contains("mono 4k") { return (134, 75, 165) }
        if m.contains("mono 2") { return (143, 89, 165) }
        if m.contains("mono") { return (130, 80, 165) }
        if m.contains("photon ultra") { return (102, 57, 165) }
        if m.contains("photon") { return (115, 65, 155) }
        if m.contains("kobra 2 max") { return (420, 420, 500) }
        if m.contains("kobra 2 plus") { return (320, 320, 400) }
        if m.contains("kobra 2 pro") { return (220, 220, 250) }
        if m.contains("kobra 2") { return (220, 220, 250) }
        return nil
    }

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
        self.maintenanceEvents = []
    }
}
