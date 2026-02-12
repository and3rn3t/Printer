//
//  SettingsView.swift
//  Printer
//
//  Created by Matt on 2/10/26.
//

import SwiftUI
import SwiftData
import OSLog

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var models: [PrintModel]
    @Query private var printers: [Printer]
    @Query private var printJobs: [PrintJob]

    // MARK: Preferences

    @AppStorage("defaultPrinterID") private var defaultPrinterID: String = ""
    @AppStorage("autoDeleteCompletedJobs") private var autoDeleteCompletedJobs = false
    @AppStorage("completedJobRetentionDays") private var completedJobRetentionDays = 30
    @AppStorage("generateThumbnails") private var generateThumbnails = true
    @AppStorage("showSlicingWarnings") private var showSlicingWarnings = true
    @AppStorage("defaultSortOption") private var defaultSortOption = "Date (Newest)"
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete = true
    @AppStorage("enablePrintNotifications") private var enablePrintNotifications = true
    @AppStorage("resinCostPerMl") private var resinCostPerMl: Double = 0.0
    @AppStorage("resinCurrency") private var resinCurrency: String = "USD"
    @AppStorage("monthlyBudget") private var monthlyBudget: Double = 0.0
    @AppStorage("enableICloudSync") private var enableICloudSync = false

    // MARK: State

    @State private var storageUsed: String = "Calculating…"
    @State private var modelCount = 0
    @State private var showingClearCacheConfirm = false
    @State private var showingDeleteAllConfirm = false
    @State private var showingClearHistoryConfirm = false
    @State private var isRescanningLibrary = false
    @State private var rescanProgress: Double = 0
    @State private var rescanTotal: Int = 0
    @State private var rescanCompleted: Int = 0
    @State private var rescanResultMessage: String?
    @State private var showingRescanResult = false
    @State private var isAnalyzingDimensions = false
    @State private var dimensionAnalysisProgress: Double = 0
    @State private var dimensionAnalysisTotal: Int = 0
    @State private var dimensionAnalysisCompleted: Int = 0
    @State private var iCloudSyncStatus: String = "Checking…"
    @State private var iCloudFileCount: Int = 0
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        NavigationStack {
            Form {
                printerSection
                librarySection
                printingSection
                notificationsSection
                costSection
                materialProfilesSection
                iCloudSection
                storageSection
                dataSection
                aboutSection
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Clear Thumbnail Cache", isPresented: $showingClearCacheConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) { clearThumbnailCache() }
            } message: {
                Text("This will remove all cached thumbnails. They will be regenerated when you view each model.")
            }
            .alert("Delete All Models", isPresented: $showingDeleteAllConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Delete All", role: .destructive) { deleteAllModels() }
            } message: {
                Text(
                    "This will permanently delete all \(models.count) models and their associated files. "
                    + "This cannot be undone."
                )
            }
            .alert("Clear Print History", isPresented: $showingClearHistoryConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) { clearPrintHistory() }
            } message: {
                Text("This will permanently delete all print job history. This cannot be undone.")
            }
            .alert("Library Scan Complete", isPresented: $showingRescanResult) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(rescanResultMessage ?? "Scan complete.")
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
            .onAppear { calculateStorage() }
        }
    }

    // MARK: - Sections

    private var printerSection: some View {
        Section {
            Picker("Default Printer", selection: $defaultPrinterID) {
                Text("None").tag("")
                ForEach(printers) { printer in
                    Text(printer.name).tag(printer.id.uuidString)
                }
            }
        } header: {
            Label("Printer", systemImage: "printer")
        } footer: {
            Text("The default printer will be pre-selected when sending a model to print.")
        }
    }

    private var librarySection: some View {
        Section {
            Picker("Default Sort", selection: $defaultSortOption) {
                ForEach(ModelSortOption.allCases) { option in
                    Text(option.rawValue).tag(option.rawValue)
                }
            }

            Toggle("Generate Thumbnails", isOn: $generateThumbnails)
            Toggle("Confirm Before Deleting", isOn: $confirmBeforeDelete)
        } header: {
            Label("Model Library", systemImage: "cube.transparent")
        } footer: {
            Text("Thumbnail generation uses SceneKit rendering and may increase import time.")
        }
    }

    @AppStorage("timelapseEnabled") private var timelapseEnabled = true
    @AppStorage("timelapseIntervalSeconds") private var timelapseIntervalSeconds: Double = 60

    private var printingSection: some View {
        Section {
            Toggle("Show Slicing Warnings", isOn: $showSlicingWarnings)

            Toggle("Auto-Delete Old Jobs", isOn: $autoDeleteCompletedJobs)

            if autoDeleteCompletedJobs {
                Stepper("Keep for \(completedJobRetentionDays) days", value: $completedJobRetentionDays, in: 1...365)
            }

            Toggle("Time-lapse Capture", isOn: $timelapseEnabled)

            if timelapseEnabled {
                VStack(alignment: .leading) {
                    Text("Capture Interval: \(Int(timelapseIntervalSeconds))s")
                        .font(.subheadline)
                    Slider(value: $timelapseIntervalSeconds, in: 10...300, step: 10)
                }
            }
        } header: {
            Label("Printing", systemImage: "paintbrush.pointed")
        } footer: {
            Text("Time-lapse captures webcam snapshots during prints for photo logs.")
        }
    }

    private var notificationsSection: some View {
        Section {
            Toggle("Print Notifications", isOn: $enablePrintNotifications)
                .onChange(of: enablePrintNotifications) { _, enabled in
                    if enabled {
                        Task {
                            await PrintNotificationManager.shared.requestAuthorization()
                        }
                    }
                }
        } header: {
            Label("Notifications", systemImage: "bell.badge")
        } footer: {
            Text("Receive a notification when a print finishes, fails, or is cancelled.")
        }
    }

    private var costSection: some View {
        Section {
            HStack {
                Text("Resin Cost")
                Spacer()
                TextField("0.00", value: $resinCostPerMl, format: .number.precision(.fractionLength(2)))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                Text("/ mL")
                    .foregroundStyle(.secondary)
            }

            Picker("Currency", selection: $resinCurrency) {
                Text("USD ($)").tag("USD")
                Text("EUR (\u{20AC})").tag("EUR")
                Text("GBP (\u{00A3})").tag("GBP")
                Text("CAD (CA$)").tag("CAD")
                Text("AUD (A$)").tag("AUD")
                Text("JPY (\u{00A5})").tag("JPY")
            }

            HStack {
                Text("Monthly Budget")
                Spacer()
                TextField("0.00", value: $monthlyBudget, format: .number.precision(.fractionLength(2)))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
            }

            NavigationLink {
                CostAnalyticsView()
            } label: {
                Label("Cost Analytics", systemImage: "chart.pie")
            }
        } header: {
            Label("Cost Tracking", systemImage: "dollarsign.circle")
        } footer: {
            Text("Set your resin cost per milliliter to see estimated costs. Set a monthly budget to track spending.")
        }
    }

    private var materialProfilesSection: some View {
        Section {
            NavigationLink {
                ResinProfileListView()
            } label: {
                Label("Material Profiles", systemImage: "drop.fill")
            }

            NavigationLink {
                InventoryView()
            } label: {
                Label("Material Inventory", systemImage: "shippingbox")
            }
        } header: {
            Label("Materials", systemImage: "drop.fill")
        } footer: {
            Text(
                "Define resin or filament profiles with cost and exposure settings. "
                + "Track physical stock levels in inventory."
            )
        }
    }

    private var iCloudSection: some View {
        Section {
            Toggle("iCloud Sync", isOn: $enableICloudSync)

            if enableICloudSync {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(iCloudSyncStatus)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Synced Files")
                    Spacer()
                    Text("\(iCloudFileCount)")
                        .foregroundStyle(.secondary)
                }

                Button("Refresh Sync Status") {
                    Task { await refreshICloudStatus() }
                }
            }
        } header: {
            Label("iCloud", systemImage: "icloud")
        } footer: {
            Text(
                "Sync your model library metadata across devices via iCloud. "
                + "Large model files are synced to iCloud Documents."
            )
        }
        .task {
            if enableICloudSync {
                await refreshICloudStatus()
            }
        }
    }

    private var storageSection: some View {
        Section {
            HStack {
                Text("Models")
                Spacer()
                Text("\(models.count)")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Print Jobs")
                Spacer()
                Text("\(printJobs.count)")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Storage Used")
                Spacer()
                Text(storageUsed)
                    .foregroundStyle(.secondary)
            }

            Button("Clear Thumbnail Cache") {
                showingClearCacheConfirm = true
            }

            // Re-scan sliced files for metadata and thumbnails
            if isRescanningLibrary {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Scanning Library…")
                        Spacer()
                        Text("\(rescanCompleted)/\(rescanTotal)")
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: rescanProgress)
                        .tint(.blue)
                        .animation(.easeInOut(duration: 0.3), value: rescanProgress)
                }
                .transition(.opacity)
            } else {
                Button {
                    rescanLibrary()
                } label: {
                    Label("Re-scan Slice Metadata", systemImage: "arrow.clockwise")
                }
                .disabled(models.isEmpty)
            }

            // Re-analyze dimensions for mesh models
            if isAnalyzingDimensions {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Analyzing Dimensions…")
                        Spacer()
                        Text("\(dimensionAnalysisCompleted)/\(dimensionAnalysisTotal)")
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: dimensionAnalysisProgress)
                        .tint(.purple)
                        .animation(.easeInOut(duration: 0.3), value: dimensionAnalysisProgress)
                }
                .transition(.opacity)
            } else {
                Button {
                    reanalyzeDimensions()
                } label: {
                    Label("Re-analyze Mesh Dimensions", systemImage: "ruler")
                }
                .disabled(models.isEmpty)
            }
        } header: {
            Label("Storage", systemImage: "internaldrive")
        } footer: {
            Text("Re-scan parses metadata and extracts thumbnails from sliced files that are missing them.")
        }
    }

    private var dataSection: some View {
        Section {
            Button("Clear Print History", role: .destructive) {
                showingClearHistoryConfirm = true
            }
            .disabled(printJobs.isEmpty)

            Button("Delete All Models", role: .destructive) {
                showingDeleteAllConfirm = true
            }
            .disabled(models.isEmpty)
        } header: {
            Label("Data Management", systemImage: "trash")
        } footer: {
            Text("Deleting models will also remove their files from disk.")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Build")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label("About", systemImage: "info.circle")
        }
    }

    // MARK: - Actions

    private func calculateStorage() {
        Task {
            guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return
            }
            let stlDir = documentsURL.appendingPathComponent("STLFiles")

            var totalSize: Int64 = 0
            if let enumerator = FileManager.default.enumerator(at: stlDir, includingPropertiesForKeys: [.fileSizeKey]) {
                while let fileURL = enumerator.nextObject() as? URL {
                    let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
                    totalSize += Int64(values?.fileSize ?? 0)
                }
            }

            await MainActor.run {
                storageUsed = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
            }
        }
    }

    private func clearThumbnailCache() {
        for model in models {
            model.thumbnailData = nil
        }
    }

    private func clearPrintHistory() {
        for job in printJobs {
            modelContext.delete(job)
        }
    }

    private func deleteAllModels() {
        var deleteErrors: [String] = []
        for model in models {
            Task {
                do {
                    try await STLFileManager.shared.deleteSTL(at: model.resolvedFileURL.path)
                } catch {
                    AppLogger.fileOps.error("Failed to delete model file \(model.name): \(error.localizedDescription)")
                    deleteErrors.append(model.name)
                }
            }
            modelContext.delete(model)
        }
        if !deleteErrors.isEmpty {
            errorMessage = "Failed to delete files for: \(deleteErrors.joined(separator: ", "))"
            showingError = true
        }
    }

    /// Re-scan all sliced models for missing metadata and thumbnails
    private func rescanLibrary() {
        let slicedModels = models.filter { $0.fileType.isSliced }
        _ = slicedModels.filter { !$0.hasSlicedMetadata }
        _ = slicedModels.filter { $0.thumbnailData == nil }

        // Models that need either metadata or thumbnail
        let modelsToScan = slicedModels.filter { !$0.hasSlicedMetadata || $0.thumbnailData == nil }

        guard !modelsToScan.isEmpty else {
            rescanResultMessage = "All \(slicedModels.count) sliced models already have metadata and thumbnails."
            showingRescanResult = true
            return
        }

        isRescanningLibrary = true
        rescanTotal = modelsToScan.count
        rescanCompleted = 0
        rescanProgress = 0

        Task {
            let parser = SlicedFileParser()
            var metadataParsed = 0
            var thumbnailsExtracted = 0

            for model in modelsToScan {
                let fileURL = model.resolvedFileURL

                // Parse metadata if missing
                if !model.hasSlicedMetadata {
                    if let metadata = await parser.parseMetadata(from: fileURL) {
                        await MainActor.run {
                            model.applyMetadata(metadata)
                        }
                        metadataParsed += 1
                    }
                }

                // Extract thumbnail if missing
                if model.thumbnailData == nil {
                    if let thumbnail = await parser.extractThumbnail(from: fileURL) {
                        await MainActor.run {
                            model.thumbnailData = thumbnail
                        }
                        thumbnailsExtracted += 1
                    }
                }

                await MainActor.run {
                    rescanCompleted += 1
                    rescanProgress = Double(rescanCompleted) / Double(rescanTotal)
                }
            }

            await MainActor.run {
                isRescanningLibrary = false

                var parts: [String] = []
                if metadataParsed > 0 { parts.append("\(metadataParsed) metadata parsed") }
                if thumbnailsExtracted > 0 { parts.append("\(thumbnailsExtracted) thumbnails extracted") }
                if parts.isEmpty {
                    rescanResultMessage = "Scanned \(modelsToScan.count) files but no new data could be extracted."
                } else {
                    rescanResultMessage = "Scanned \(modelsToScan.count) files: \(parts.joined(separator: ", "))."
                }
                showingRescanResult = true
            }
        }
    }

    /// Re-analyze all mesh models that are missing dimension data
    private func reanalyzeDimensions() {
        let meshModels = models.filter { $0.fileType.needsSlicing && !$0.hasDimensions }

        guard !meshModels.isEmpty else {
            rescanResultMessage = "All mesh models already have dimension data."
            showingRescanResult = true
            return
        }

        isAnalyzingDimensions = true
        dimensionAnalysisTotal = meshModels.count
        dimensionAnalysisCompleted = 0
        dimensionAnalysisProgress = 0

        Task {
            let analyzer = MeshAnalyzer()
            var analyzed = 0

            for model in meshModels {
                if let info = try? await analyzer.analyze(url: model.resolvedFileURL) {
                    await MainActor.run {
                        model.applyMeshInfo(info)
                    }
                    analyzed += 1
                }

                await MainActor.run {
                    dimensionAnalysisCompleted += 1
                    dimensionAnalysisProgress = Double(dimensionAnalysisCompleted) / Double(dimensionAnalysisTotal)
                }
            }

            await MainActor.run {
                isAnalyzingDimensions = false
                rescanResultMessage = "Analyzed \(meshModels.count) mesh models: \(analyzed) dimensions extracted."
                showingRescanResult = true
            }
        }
    }

    // MARK: - iCloud Sync

    private func refreshICloudStatus() async {
        let syncManager = CloudSyncManager.shared
        let status = await syncManager.getSyncStatus()
        await MainActor.run {
            if status.isAvailable {
                iCloudSyncStatus = "Available"
                iCloudFileCount = status.fileCount
            } else {
                iCloudSyncStatus = "Unavailable"
                iCloudFileCount = 0
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(
        for: PrintModel.self, PrintJob.self, Printer.self, configurations: config
    )

    return SettingsView()
        .modelContainer(container)
}
