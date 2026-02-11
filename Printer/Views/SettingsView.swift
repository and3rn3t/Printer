//
//  SettingsView.swift
//  Printer
//
//  Created by Matt on 2/10/26.
//

import SwiftUI
import SwiftData

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

    // MARK: State

    @State private var storageUsed: String = "Calculating…"
    @State private var modelCount = 0
    @State private var showingClearCacheConfirm = false
    @State private var showingDeleteAllConfirm = false
    @State private var showingClearHistoryConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                printerSection
                librarySection
                printingSection
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
                Text("This will permanently delete all \(models.count) models and their associated files. This cannot be undone.")
            }
            .alert("Clear Print History", isPresented: $showingClearHistoryConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) { clearPrintHistory() }
            } message: {
                Text("This will permanently delete all print job history. This cannot be undone.")
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

    private var printingSection: some View {
        Section {
            Toggle("Show Slicing Warnings", isOn: $showSlicingWarnings)

            Toggle("Auto-Delete Old Jobs", isOn: $autoDeleteCompletedJobs)

            if autoDeleteCompletedJobs {
                Stepper("Keep for \(completedJobRetentionDays) days", value: $completedJobRetentionDays, in: 1...365)
            }
        } header: {
            Label("Printing", systemImage: "paintbrush.pointed")
        } footer: {
            Text("Slicing warnings remind you when a model format isn't directly printable on resin printers.")
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
        } header: {
            Label("Storage", systemImage: "internaldrive")
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
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let stlDir = documentsURL.appendingPathComponent("STLFiles")

            var totalSize: Int64 = 0
            if let enumerator = FileManager.default.enumerator(at: stlDir, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let fileURL as URL in enumerator {
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
        for model in models {
            Task {
                try? await STLFileManager.shared.deleteSTL(at: model.resolvedFileURL.path)
            }
            modelContext.delete(model)
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: PrintModel.self, PrintJob.self, Printer.self,
        configurations: config
    )

    return SettingsView()
        .modelContainer(container)
}
