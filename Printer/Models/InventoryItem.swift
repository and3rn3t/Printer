//
//  InventoryItem.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import Foundation
import SwiftData

/// Represents a physical unit of material (resin bottle or filament spool) in stock.
///
/// Tracks initial volume, current remaining volume, purchase info, and expiry.
/// Linked to a `ResinProfile` for per-material tracking.
@Model
final class InventoryItem {
    @Attribute(.unique) var id: UUID

    /// Human-readable label (e.g. "Elegoo Grey 500mL #2")
    var name: String

    /// Initial volume in milliliters (mL for resin, grams for filament)
    var initialVolume: Double

    /// Remaining volume in milliliters (auto-deducted on print completion)
    var remainingVolume: Double

    /// Date this item was purchased
    var purchaseDate: Date?

    /// Date this item expires (relevant for resins)
    var expiryDate: Date?

    /// Cost paid for this unit
    var purchaseCost: Double?

    /// The material profile this stock belongs to
    var resinProfile: ResinProfile?

    /// Whether this item is currently open/in-use
    var isOpened: Bool

    /// Notes about this item
    var notes: String

    /// Low stock threshold in mL — alert when remaining drops below this
    var lowStockThreshold: Double

    /// Date this record was created
    var createdDate: Date

    /// Whether this item is below the low-stock threshold
    var isLowStock: Bool {
        remainingVolume <= lowStockThreshold && remainingVolume > 0
    }

    /// Whether this item is depleted
    var isDepleted: Bool {
        remainingVolume <= 0
    }

    /// Usage percentage (0.0–1.0)
    var usagePercentage: Double {
        guard initialVolume > 0 else { return 0 }
        return max(0, min(1, 1.0 - (remainingVolume / initialVolume)))
    }

    /// Whether this item has expired
    var isExpired: Bool {
        guard let expiry = expiryDate else { return false }
        return Date() > expiry
    }

    /// Formatted remaining volume
    var formattedRemaining: String {
        if resinProfile?.materialType.isResin == true {
            return String(format: "%.0f mL", remainingVolume)
        } else {
            return String(format: "%.0f g", remainingVolume)
        }
    }

    /// Deduct volume after a completed print
    func deduct(_ volumeMl: Double) {
        remainingVolume = max(0, remainingVolume - volumeMl)
    }

    init(
        name: String,
        initialVolume: Double,
        resinProfile: ResinProfile? = nil,
        purchaseDate: Date? = nil,
        expiryDate: Date? = nil,
        purchaseCost: Double? = nil,
        lowStockThreshold: Double = 50,
        notes: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.initialVolume = initialVolume
        self.remainingVolume = initialVolume
        self.resinProfile = resinProfile
        self.purchaseDate = purchaseDate
        self.expiryDate = expiryDate
        self.purchaseCost = purchaseCost
        self.isOpened = false
        self.lowStockThreshold = lowStockThreshold
        self.notes = notes
        self.createdDate = Date()
    }
}
