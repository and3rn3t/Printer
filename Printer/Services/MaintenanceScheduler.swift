//
//  MaintenanceScheduler.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import Foundation
import SwiftData

/// Computes maintenance status for a printer based on print hours/count since last event
/// and recommended intervals.
///
/// Used by dashboard and printer detail to surface proactive maintenance alerts.
struct MaintenanceScheduler {

    /// A maintenance task that is due or upcoming.
    struct MaintenanceAlert: Identifiable {
        let id = UUID()
        let type: MaintenanceType
        let printerName: String
        let printerID: UUID
        /// Negative = overdue by N days, positive = due in N days
        let daysUntilDue: Int
        /// Last time this type of maintenance was performed (nil if never)
        let lastPerformed: Date?

        var isOverdue: Bool { daysUntilDue < 0 }
        var isDueSoon: Bool { daysUntilDue >= 0 && daysUntilDue <= 7 }

        var urgency: Urgency {
            if daysUntilDue < 0 { return .overdue }
            if daysUntilDue <= 3 { return .critical }
            if daysUntilDue <= 7 { return .upcoming }
            return .scheduled
        }

        enum Urgency: Comparable {
            case overdue, critical, upcoming, scheduled

            var color: String {
                switch self {
                case .overdue: return "red"
                case .critical: return "orange"
                case .upcoming: return "yellow"
                case .scheduled: return "blue"
                }
            }
        }

        var displayText: String {
            if daysUntilDue < 0 {
                return "\(abs(daysUntilDue))d overdue"
            } else if daysUntilDue == 0 {
                return "Due today"
            } else {
                return "Due in \(daysUntilDue)d"
            }
        }
    }

    /// Compute all maintenance alerts across all printers.
    ///
    /// For each printer, checks every maintenance type that has at least one logged event
    /// with a non-zero reminder interval. Returns alerts sorted by urgency.
    static func computeAlerts(printers: [Printer]) -> [MaintenanceAlert] {
        var alerts: [MaintenanceAlert] = []
        let now = Date()
        let calendar = Calendar.current

        for printer in printers {
            // Group events by type, keep the most recent per type
            var latestByType: [MaintenanceType: MaintenanceEvent] = [:]
            for event in printer.maintenanceEvents {
                if let existing = latestByType[event.maintenanceType] {
                    if event.date > existing.date {
                        latestByType[event.maintenanceType] = event
                    }
                } else {
                    latestByType[event.maintenanceType] = event
                }
            }

            // Check each tracked maintenance type
            for (type, lastEvent) in latestByType {
                guard lastEvent.reminderIntervalDays > 0 else { continue }
                guard let nextDue = lastEvent.nextDueDate else { continue }

                let daysLeft = calendar.dateComponents(
                    [.day],
                    from: calendar.startOfDay(for: now),
                    to: calendar.startOfDay(for: nextDue)
                ).day ?? 0

                // Only surface alerts that are due within 14 days or overdue
                if daysLeft <= 14 {
                    alerts.append(MaintenanceAlert(
                        type: type,
                        printerName: printer.name,
                        printerID: printer.id,
                        daysUntilDue: daysLeft,
                        lastPerformed: lastEvent.date
                    ))
                }
            }
        }

        // Sort: overdue first, then by days until due
        return alerts.sorted { $0.daysUntilDue < $1.daysUntilDue }
    }

    /// Compute alerts for a single printer.
    static func alertsForPrinter(_ printer: Printer) -> [MaintenanceAlert] {
        computeAlerts(printers: [printer])
    }

    /// Check and send notifications for overdue maintenance.
    /// Should be called periodically (e.g., on app launch or daily).
    static func checkAndNotify(printers: [Printer]) {
        let alerts = computeAlerts(printers: printers).filter { $0.isOverdue }

        for alert in alerts {
            PrintNotificationManager.shared.notifyMaintenanceDue(
                type: alert.type.rawValue,
                printerName: alert.printerName,
                daysOverdue: abs(alert.daysUntilDue)
            )
        }
    }
}
