//
//  MaintenanceEvent.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import Foundation
import SwiftData

/// Types of maintenance that can be logged for a printer.
enum MaintenanceType: String, Codable, CaseIterable, Identifiable {
    case fepReplacement = "FEP Replacement"
    case vatCleaning = "Vat Cleaning"
    case bedLeveling = "Bed Leveling"
    case resinChange = "Resin Change"
    case firmwareUpdate = "Firmware Update"
    case nozzleClean = "Nozzle Clean"
    case beltTension = "Belt Tension"
    case lubrication = "Lubrication"
    case generalService = "General Service"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .fepReplacement: return "film"
        case .vatCleaning: return "drop.triangle"
        case .bedLeveling: return "level"
        case .resinChange: return "waterbottle"
        case .firmwareUpdate: return "arrow.down.app"
        case .nozzleClean: return "flame"
        case .beltTension: return "gearshape.2"
        case .lubrication: return "oilcan"
        case .generalService: return "wrench.and.screwdriver"
        }
    }

    /// Suggested interval in days between maintenance events (0 = no schedule)
    var suggestedIntervalDays: Int {
        switch self {
        case .fepReplacement: return 90
        case .vatCleaning: return 7
        case .bedLeveling: return 30
        case .resinChange: return 14
        case .firmwareUpdate: return 0
        case .nozzleClean: return 14
        case .beltTension: return 60
        case .lubrication: return 90
        case .generalService: return 0
        }
    }
}

/// A maintenance event recorded for a specific printer.
@Model
final class MaintenanceEvent {
    @Attribute(.unique) var id: UUID
    var date: Date
    var maintenanceType: MaintenanceType
    var notes: String
    var cost: Double?

    /// The printer this event belongs to
    var printer: Printer?

    /// Reminder interval in days from this event (0 = no reminder)
    var reminderIntervalDays: Int

    /// Whether a reminder notification has been sent for the next due date
    var reminderSent: Bool

    /// Computed next-due date based on this event + reminder interval
    var nextDueDate: Date? {
        guard reminderIntervalDays > 0 else { return nil }
        return Calendar.current.date(byAdding: .day, value: reminderIntervalDays, to: date)
    }

    /// Whether maintenance is overdue
    var isOverdue: Bool {
        guard let due = nextDueDate else { return false }
        return Date() > due
    }

    /// Days until next maintenance (negative = overdue)
    var daysUntilDue: Int? {
        guard let due = nextDueDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: due).day
    }

    init(
        maintenanceType: MaintenanceType,
        notes: String = "",
        cost: Double? = nil,
        reminderIntervalDays: Int? = nil
    ) {
        self.id = UUID()
        self.date = Date()
        self.maintenanceType = maintenanceType
        self.notes = notes
        self.cost = cost
        self.reminderIntervalDays = reminderIntervalDays ?? maintenanceType.suggestedIntervalDays
        self.reminderSent = false
    }
}
