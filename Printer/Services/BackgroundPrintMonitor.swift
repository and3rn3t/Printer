//
//  BackgroundPrintMonitor.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import Foundation
import SwiftData
import OSLog
#if os(iOS)
import BackgroundTasks
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Background task identifier for print monitoring
let backgroundPrintMonitorTaskID = "com.printer3d.printMonitor"

/// Monitors active prints in the background using BGTaskScheduler.
///
/// Periodically polls printer status, sends milestone notifications (25%, 50%, 75%),
/// and updates the widget data. Reschedules itself while prints are active.
actor BackgroundPrintMonitor {
    static let shared = BackgroundPrintMonitor()

    /// Milestones that trigger notifications (percentage thresholds)
    private let milestones: Set<Int> = [25, 50, 75, 100]

    /// Tracks which milestones have already been notified per printer
    private var notifiedMilestones: [String: Set<Int>] = [:]

    /// Shared model container — injected once to avoid re-creation on every poll
    private var modelContainer: ModelContainer?

    /// Inject the shared ModelContainer (call once at app launch)
    func configure(with container: ModelContainer) {
        self.modelContainer = container
    }

    // MARK: - Registration

    #if os(iOS)
    /// Register the background task with BGTaskScheduler. Call once at app launch.
    nonisolated func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundPrintMonitorTaskID,
            using: nil
        ) { task in
            guard let bgTask = task as? BGAppRefreshTask else { return }
            Task {
                await self.handleBackgroundTask(bgTask)
            }
        }
    }

    /// Schedule the next background refresh. Should be called when a print starts.
    nonisolated func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundPrintMonitorTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60) // 5 minutes
        do {
            try BGTaskScheduler.shared.submit(request)
            AppLogger.background.info("Scheduled background print refresh")
        } catch {
            AppLogger.background.warning("Failed to schedule background refresh: \(error.localizedDescription)")
            // Non-fatal — background monitoring won't work, but in-app monitoring will
        }
    }

    // MARK: - Background Task Handler

    private func handleBackgroundTask(_ task: BGAppRefreshTask) async {
        // Set up expiration handler
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        let hasActivePrints = await pollAllPrinters()

        // Reschedule if there are still active prints
        if hasActivePrints {
            scheduleBackgroundRefresh()
        }

        task.setTaskCompleted(success: true)
    }
    #endif

    // MARK: - Polling

    /// Poll all known printers and check for active prints. Returns true if any printer is actively printing.
    func pollAllPrinters() async -> Bool {
        // Use the injected container, falling back to creating one only if needed
        let container: ModelContainer
        if let existing = modelContainer {
            container = existing
        } else {
            guard let fallback = try? ModelContainer(
                for: Printer.self,
                PrintJob.self,
                PrintModel.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: false)
            ) else {
                AppLogger.background.error("Failed to create ModelContainer for background polling")
                return false
            }
            container = fallback
            self.modelContainer = fallback
        }

        let context = ModelContext(container)
        guard let printers = try? context.fetch(FetchDescriptor<Printer>()) else {
            AppLogger.background.error("Failed to fetch printers for background polling")
            return false
        }

        var anyActive = false

        for printer in printers {
            let result = await checkPrinterStatus(printer)

            if result.isPrinting {
                anyActive = true

                // Check for milestones
                if let progress = result.progress {
                    let pct = Int(progress * 100)
                    await checkMilestones(
                        printerName: printer.name,
                        fileName: result.fileName,
                        percentage: pct,
                        estimatedRemaining: result.estimatedTimeRemaining
                    )
                }

                // Detect completion
                if let progress = result.progress, progress >= 1.0 {
                    PrintNotificationManager.shared.notifyPrintFinished(
                        fileName: result.fileName,
                        printerName: printer.name,
                        status: "completed",
                        duration: 0
                    )
                    notifiedMilestones[printer.name] = nil
                }
            }
        }

        return anyActive
    }

    /// Check a single printer's status via its protocol.
    private func checkPrinterStatus(_ printer: Printer) async -> PrinterPollResult {
        switch printer.printerProtocol {
        case .act:
            let service = PhotonPrinterService.shared
            do {
                let status = try await service.getStatus(ipAddress: printer.ipAddress, port: printer.port)
                let isPrinting = status == .printing || status == .paused
                return PrinterPollResult(
                    isPrinting: isPrinting, progress: nil, fileName: nil, estimatedTimeRemaining: nil
                )
            } catch {
                AppLogger.background.debug(
                    "Background ACT poll failed for \(printer.name): \(error.localizedDescription)"
                )
                return PrinterPollResult(
                    isPrinting: false, progress: nil, fileName: nil, estimatedTimeRemaining: nil
                )
            }

        case .octoprint:
            let api = AnycubicPrinterAPI.shared
            do {
                let job = try await api.getJobStatus(ipAddress: printer.ipAddress, apiKey: printer.apiKey)
                let isPrinting = job.state.lowercased().contains("printing")
                let progress = job.progress?.completion.map { $0 / 100.0 }
                let timeLeft = job.progress?.printTimeLeft
                let fileName = job.job?.file?.name
                return PrinterPollResult(
                    isPrinting: isPrinting,
                    progress: progress,
                    fileName: fileName,
                    estimatedTimeRemaining: timeLeft
                )
            } catch {
                AppLogger.background.debug(
                    "Background HTTP poll failed for \(printer.name): \(error.localizedDescription)"
                )
                return PrinterPollResult(
                    isPrinting: false, progress: nil, fileName: nil, estimatedTimeRemaining: nil
                )
            }

        case .anycubicHTTP:
            return PrinterPollResult(isPrinting: false, progress: nil, fileName: nil, estimatedTimeRemaining: nil)
        }
    }

    // MARK: - Milestones

    private func checkMilestones(
        printerName: String,
        fileName: String?,
        percentage: Int,
        estimatedRemaining: Double?
    ) async {
        var sent = notifiedMilestones[printerName] ?? []

        for milestone in milestones.sorted() {
            if percentage >= milestone && !sent.contains(milestone) {
                sent.insert(milestone)
                if milestone < 100 {
                    PrintNotificationManager.shared.notifyPrintMilestone(
                        fileName: fileName,
                        printerName: printerName,
                        milestone: milestone,
                        estimatedTimeRemaining: estimatedRemaining
                    )
                }
            }
        }

        notifiedMilestones[printerName] = sent
    }

    /// Reset milestone tracking for a printer (call when a new print starts)
    func resetMilestones(for printerName: String) {
        notifiedMilestones[printerName] = nil
    }
}

// MARK: - Poll Result

nonisolated private struct PrinterPollResult {
    let isPrinting: Bool
    let progress: Double?
    let fileName: String?
    let estimatedTimeRemaining: Double?
}
