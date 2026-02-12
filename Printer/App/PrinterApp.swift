//
//  PrinterApp.swift
//  Printer
//
//  Created by Matt on 2/10/26.
//

import SwiftUI
import SwiftData
import WidgetKit
import OSLog
#if os(iOS)
import BackgroundTasks
#endif

@main
struct PrinterApp: App {
    @AppStorage("autoDeleteCompletedJobs") private var autoDeleteCompletedJobs = false
    @AppStorage("completedJobRetentionDays") private var completedJobRetentionDays = 30

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            PrintModel.self,
            PrintJob.self,
            Printer.self,
            ModelCollection.self,
            MaintenanceEvent.self,
            ResinProfile.self,
            SavedFilter.self,
            InventoryItem.self,
            PrintSnapshot.self,
        ])

        let iCloudEnabled = UserDefaults.standard.bool(forKey: "enableICloudSync")
        let modelConfiguration: ModelConfiguration

        if iCloudEnabled {
            modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
        } else {
            modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Log the error before crashing — helps diagnose schema migration failures
            AppLogger.data.critical("ModelContainer creation failed: \(error.localizedDescription)")
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        #if os(iOS)
        BackgroundPrintMonitor.shared.registerBackgroundTask()
        #endif

        // Inject shared container into background monitor to avoid per-poll creation
        let container = sharedModelContainer
        Task {
            await BackgroundPrintMonitor.shared.configure(with: container)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    cleanupOldJobs()
                    updateWidgetData()
                    // Request notification permission if enabled
                    if UserDefaults.standard.bool(forKey: "enablePrintNotifications") {
                        await PrintNotificationManager.shared.requestAuthorization()
                    }
                    // Schedule background print monitoring
                    #if os(iOS)
                    BackgroundPrintMonitor.shared.scheduleBackgroundRefresh()
                    #endif
                    // Check for overdue maintenance
                    checkMaintenanceAlerts()
                }
        }
        .modelContainer(sharedModelContainer)
    }

    // MARK: - Widget Data Update

    /// Write current printer/model/job data to shared UserDefaults for widget display
    private func updateWidgetData() {
        let context = sharedModelContainer.mainContext

        do {
            let printers = try context.fetch(FetchDescriptor<Printer>())
            let modelCount = try context.fetchCount(FetchDescriptor<PrintModel>())
            let allJobs = try context.fetch(FetchDescriptor<PrintJob>())

            let completedCount = allJobs.filter { $0.status == .completed }.count
            let finishedCount = allJobs.filter { $0.status == .completed || $0.status == .failed }.count
            let successRate = finishedCount > 0 ? Int(Double(completedCount) / Double(finishedCount) * 100) : 0

            let printerStates = printers.map { printer in
                WidgetPrinterState(
                    id: printer.id,
                    name: printer.name,
                    ipAddress: printer.ipAddress,
                    printerProtocol: printer.printerProtocol.rawValue,
                    isOnline: printer.isConnected,
                    statusText: printer.isConnected ? "Online" : "Offline",
                    isPrinting: false,
                    fileName: nil,
                    progress: nil,
                    lastUpdated: Date()
                )
            }

            let widgetData = WidgetData(
                printers: printerStates,
                modelCount: modelCount,
                printJobCount: allJobs.count,
                successRate: successRate
            )
            widgetData.save()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            AppLogger.app.warning("Failed to update widget data: \(error.localizedDescription)")
        }
    }

    // MARK: - Maintenance Checks

    /// Check for overdue maintenance and send notifications.
    private func checkMaintenanceAlerts() {
        let context = sharedModelContainer.mainContext
        do {
            let printers = try context.fetch(FetchDescriptor<Printer>())
            MaintenanceScheduler.checkAndNotify(printers: printers)
        } catch {
            AppLogger.app.warning("Failed to check maintenance alerts: \(error.localizedDescription)")
        }
    }

    // MARK: - Job Cleanup

    /// Delete completed/failed/cancelled print jobs older than the configured retention period.
    private func cleanupOldJobs() {
        guard autoDeleteCompletedJobs else { return }
        let context = sharedModelContainer.mainContext
        let cutoff = Calendar.current.date(byAdding: .day, value: -completedJobRetentionDays, to: Date()) ?? Date()

        do {
            // Fetch jobs older than cutoff, then filter terminal status in memory
            // (SwiftData #Predicate doesn't support non-RawRepresentable enum comparison)
            var descriptor = FetchDescriptor<PrintJob>(
                predicate: #Predicate<PrintJob> { $0.startDate < cutoff }
            )
            descriptor.fetchLimit = 1000 // Safety cap for large databases
            let candidates = try context.fetch(descriptor)
            let oldJobs = candidates.filter {
                $0.status == .completed || $0.status == .failed || $0.status == .cancelled
            }

            guard !oldJobs.isEmpty else { return }
            for job in oldJobs {
                context.delete(job)
            }
            try context.save()
            AppLogger.data.info("Cleaned up \(oldJobs.count) old print jobs")
        } catch {
            AppLogger.data.warning("Failed to cleanup old jobs: \(error.localizedDescription)")
        }
    }
}
