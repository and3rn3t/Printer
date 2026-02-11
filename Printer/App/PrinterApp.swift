//
//  PrinterApp.swift
//  Printer
//
//  Created by Matt on 2/10/26.
//

import SwiftUI
import SwiftData

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
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    cleanupOldJobs()
                    // Request notification permission if enabled
                    if UserDefaults.standard.bool(forKey: "enablePrintNotifications") {
                        await PrintNotificationManager.shared.requestAuthorization()
                    }
                }
        }
        .modelContainer(sharedModelContainer)
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

