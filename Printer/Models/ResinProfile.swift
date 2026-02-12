//
//  ResinProfile.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import Foundation
import SwiftData

/// A resin or filament material profile.
///
/// Users can define specific resins (brand, color, exposure times, cost)
/// and associate them with print jobs for accurate per-material tracking.
@Model
final class ResinProfile {
    @Attribute(.unique) var id: UUID
    var name: String
    var brand: String
    var color: String
    var colorHex: String

    /// Cost per milliliter
    var costPerMl: Double

    /// Recommended normal exposure time in seconds
    var normalExposure: Float?
    /// Recommended bottom exposure time in seconds
    var bottomExposure: Float?
    /// Recommended bottom layers count
    var bottomLayers: Int?
    /// Recommended layer height in mm
    var recommendedLayerHeight: Float?

    /// Type of material
    var materialType: MaterialType

    /// Optional notes (e.g. wash & cure instructions)
    var notes: String

    /// Date this profile was created
    var createdDate: Date

    /// Print jobs that used this profile
    @Relationship(deleteRule: .nullify, inverse: \PrintJob.resinProfile)
    var printJobs: [PrintJob]

    init(
        name: String,
        brand: String = "",
        color: String = "",
        colorHex: String = "808080",
        costPerMl: Double = 0,
        materialType: MaterialType = .standardResin,
        notes: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.brand = brand
        self.color = color
        self.colorHex = colorHex
        self.costPerMl = costPerMl
        self.materialType = materialType
        self.notes = notes
        self.createdDate = Date()
        self.printJobs = []
    }
}

/// Material type classification
enum MaterialType: String, Codable, CaseIterable, Identifiable {
    case standardResin = "Standard Resin"
    case absLikeResin = "ABS-Like Resin"
    case waterWashable = "Water Washable"
    case plantBased = "Plant-Based"
    case tough = "Tough Resin"
    case flexible = "Flexible Resin"
    case castable = "Castable Resin"
    case dental = "Dental Resin"
    case pla = "PLA"
    case abs = "ABS"
    case petg = "PETG"
    case tpu = "TPU"
    case nylon = "Nylon"

    var id: String { rawValue }

    var isResin: Bool {
        switch self {
        case .pla, .abs, .petg, .tpu, .nylon: return false
        default: return true
        }
    }

    var icon: String {
        isResin ? "drop.fill" : "circle.dotted"
    }
}
