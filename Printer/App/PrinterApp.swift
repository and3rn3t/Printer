//
//  PrinterApp.swift
//  Printer
//
//  Created by Matt on 2/10/26.
//

import SwiftUI
import SwiftData
import WidgetKit
import BackgroundTasks

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
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        BackgroundPrintMonitor.shared.registerBackgroundTask()
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
                    BackgroundPrintMonitor.shared.scheduleBackgroundRefresh()
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
            // Non-fatal — widget data will be stale
        }
    }

    // MARK: - Job Cleanup

    /// Delete completed/failed/cancelled print jobs older than the configured retention period.
    private func cleanupOldJobs() {
        guard autoDeleteCompletedJobs else { return }
        let context = sharedModelContainer.mainContext
        let cutoff = Calendar.current.date(byAdding: .day, value: -completedJobRetentionDays, to: Date()) ?? Date()

        do {
            let descriptor = FetchDescriptor<PrintJob>()
            let allJobs = try context.fetch(descriptor)
            var deletedCount = 0

            for job in allJobs {
                let isTerminal = job.status == .completed || job.status == .failed || job.status == .cancelled
                guard isTerminal, job.startDate < cutoff else { continue }
                context.delete(job)
                deletedCount += 1
            }

            if deletedCount > 0 {
                try context.save()
            }
        } catch {
            // Non-fatal — cleanup will retry next launch
        }
    }
}

