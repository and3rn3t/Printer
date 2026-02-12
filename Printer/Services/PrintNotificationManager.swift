//
//  PrintNotificationManager.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import Foundation
import UserNotifications
import OSLog

/// Manages local notifications for print job state changes.
///
/// Posts notifications when prints complete, fail, or are cancelled while
/// the app is backgrounded. Respects the user's notification preference
/// stored in `UserDefaults` under the `enablePrintNotifications` key.
nonisolated final class PrintNotificationManager: @unchecked Sendable {
    static let shared = PrintNotificationManager()

    // MARK: - Notification Categories

    private enum Category {
        static let printComplete = "PRINT_COMPLETE"
        static let printFailed = "PRINT_FAILED"
    }

    private init() {}

    // MARK: - Permission

    /// Request notification authorization. Safe to call multiple times.
    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                await registerCategories()
            }
        } catch {
            AppLogger.background.warning("Notification authorization request failed: \(error.localizedDescription)")
            // Non-fatal — user simply won't get notifications
        }
    }

    /// Register notification action categories
    private func registerCategories() async {
        let center = UNUserNotificationCenter.current()

        let completedCategory = UNNotificationCategory(
            identifier: Category.printComplete,
            actions: [],
            intentIdentifiers: []
        )

        let failedCategory = UNNotificationCategory(
            identifier: Category.printFailed,
            actions: [],
            intentIdentifiers: []
        )

        center.setNotificationCategories([completedCategory, failedCategory])
    }

    // MARK: - Post Notifications

    /// Send a notification when a print job finishes.
    ///
    /// - Parameters:
    ///   - fileName: Name of the file that was printing
    ///   - printerName: Name of the printer
    ///   - status: Final status (completed, failed, cancelled)
    ///   - duration: Total print duration in seconds
    func notifyPrintFinished(
        fileName: String?,
        printerName: String,
        status: String,
        duration: TimeInterval
    ) {
        guard UserDefaults.standard.bool(forKey: "enablePrintNotifications") else { return }

        let content = UNMutableNotificationContent()

        let displayName = fileName ?? "Print job"

        switch status.lowercased() {
        case "completed":
            content.title = "Print Complete \u{2705}"
            content.body = "\(displayName) on \(printerName) finished successfully"
            if duration > 0 {
                content.body += " in \(Self.formatDurationLocal(duration))"
            }
            content.categoryIdentifier = Category.printComplete
            content.sound = .default

        case "failed":
            content.title = "Print Failed \u{274C}"
            content.body = "\(displayName) on \(printerName) has failed"
            content.categoryIdentifier = Category.printFailed
            content.sound = UNNotificationSound.defaultCritical

        case "cancelled":
            content.title = "Print Cancelled"
            content.body = "\(displayName) on \(printerName) was cancelled"
            content.categoryIdentifier = Category.printFailed
            content.sound = .default

        default:
            content.title = "Print Update"
            content.body = "\(displayName) on \(printerName): \(status)"
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Milestone Notifications

    /// Send a milestone notification (e.g. 25%, 50%, 75% complete).
    func notifyPrintMilestone(
        fileName: String?,
        printerName: String,
        milestone: Int,
        estimatedTimeRemaining: TimeInterval?
    ) {
        guard UserDefaults.standard.bool(forKey: "enablePrintNotifications") else { return }

        let content = UNMutableNotificationContent()
        let displayName = fileName ?? "Print"

        content.title = "\(displayName) — \(milestone)% Complete"

        if let remaining = estimatedTimeRemaining, remaining > 0 {
            content.body = "\(printerName) · ~\(Self.formatDurationLocal(remaining)) remaining"
        } else {
            content.body = "Printing on \(printerName)"
        }
        content.sound = .default
        content.threadIdentifier = "print-progress"

        let request = UNNotificationRequest(
            identifier: "milestone-\(printerName)-\(milestone)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Finishing Soon Notification

    /// Send a notification when a print is almost done (< 10 minutes remaining).
    func notifyPrintFinishingSoon(
        fileName: String?,
        printerName: String,
        estimatedTimeRemaining: TimeInterval
    ) {
        guard UserDefaults.standard.bool(forKey: "enablePrintNotifications") else { return }

        let content = UNMutableNotificationContent()
        let displayName = fileName ?? "Print"

        content.title = "\(displayName) — Finishing Soon"
        content.body = "\(printerName) · ~\(Self.formatDurationLocal(estimatedTimeRemaining)) remaining"
        content.sound = .default
        content.threadIdentifier = "print-progress"

        let request = UNNotificationRequest(
            identifier: "finishing-soon-\(printerName)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Low Stock Notification

    /// Notify when a material inventory item is running low.
    func notifyLowStock(itemName: String, remaining: Double, unit: String) {
        guard UserDefaults.standard.bool(forKey: "enablePrintNotifications") else { return }

        let content = UNMutableNotificationContent()
        content.title = "Low Stock: \(itemName)"
        content.body = "Only \(Int(remaining)) \(unit) remaining"
        content.sound = .default
        content.threadIdentifier = "inventory"

        let request = UNNotificationRequest(
            identifier: "low-stock-\(itemName)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Notify when a maintenance task is overdue for a printer.
    func notifyMaintenanceDue(type: String, printerName: String, daysOverdue: Int) {
        guard UserDefaults.standard.bool(forKey: "enablePrintNotifications") else { return }

        let content = UNMutableNotificationContent()
        content.title = "Maintenance Overdue"
        content.body = "\(type) for \(printerName) is \(daysOverdue) day\(daysOverdue == 1 ? "" : "s") overdue"
        content.sound = .default
        content.threadIdentifier = "maintenance"

        let request = UNNotificationRequest(
            identifier: "maintenance-\(printerName)-\(type)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Helpers

    private static func formatDurationLocal(_ seconds: TimeInterval) -> String {
        formatDuration(Double(seconds))
    }
}
