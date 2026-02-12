//
//  PrinterFileBrowserView.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import SwiftUI

/// Browse and manage files stored on an OctoPrint-compatible printer.
///
/// Shows the list of files on the printer with options to start printing or delete files.
/// Only available for OctoPrint printers (not ACT protocol).
struct PrinterFileBrowserView: View {
    let printer: Printer

    @State private var files: [PrinterFile] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var fileToDelete: PrinterFile?
    @State private var showingDeleteConfirm = false
    @State private var isPrinting = false

    var body: some View {
        Group {
            if isLoading && files.isEmpty {
                ProgressView("Loading files…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if files.isEmpty {
                ContentUnavailableView(
                    "No Files",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("No files found on the printer")
                )
            } else {
                List {
                    ForEach(files) { file in
                        PrinterFileRow(
                            file: file,
                            onPrint: { startPrint(file: file) },
                            onDelete: {
                                fileToDelete = file
                                showingDeleteConfirm = true
                            }
                        )
                    }
                }
            }
        }
        .navigationTitle("Printer Files")
        .refreshable {
            await loadFiles()
        }
        .task {
            await loadFiles()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .alert("Delete File", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) { fileToDelete = nil }
            Button("Delete", role: .destructive) {
                if let file = fileToDelete {
                    deleteFile(file)
                }
            }
        } message: {
            Text("Delete \"\(fileToDelete?.name ?? "")\" from the printer? This cannot be undone.")
        }
        .overlay {
            if isPrinting {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Starting print…")
                            .font(.headline)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    // MARK: - Actions

    private func loadFiles() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let api = AnycubicPrinterAPI.shared
            let result = try await api.listFiles(
                ipAddress: printer.ipAddress,
                apiKey: printer.apiKey
            )
            files = result.sorted { ($0.name) < ($1.name) }
        } catch {
            errorMessage = "Failed to load files: \(error.localizedDescription)"
            showingError = true
        }
    }

    private func startPrint(file: PrinterFile) {
        isPrinting = true
        Task {
            do {
                let api = AnycubicPrinterAPI.shared
                try await api.startPrint(
                    ipAddress: printer.ipAddress,
                    apiKey: printer.apiKey,
                    filename: file.name,
                    protocol: printer.printerProtocol
                )
                isPrinting = false
            } catch {
                isPrinting = false
                errorMessage = "Failed to start print: \(error.localizedDescription)"
                showingError = true
            }
        }
    }

    private func deleteFile(_ file: PrinterFile) {
        Task {
            do {
                let api = AnycubicPrinterAPI.shared
                try await api.deleteFile(
                    ipAddress: printer.ipAddress,
                    apiKey: printer.apiKey,
                    filename: file.name
                )
                files.removeAll { $0.id == file.id }
            } catch {
                errorMessage = "Failed to delete file: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
}

// MARK: - Printer File Row

struct PrinterFileRow: View {
    let file: PrinterFile
    let onPrint: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: fileIcon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(file.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let size = file.size {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let date = file.date {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                onPrint()
            } label: {
                Label("Print", systemImage: "printer")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button {
                onPrint()
            } label: {
                Label("Print", systemImage: "printer")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var fileIcon: String {
        let ext = (file.name as NSString).pathExtension.lowercased()
        switch ext {
        case "gcode": return "doc.text"
        case "stl": return "cube"
        case "ctb", "pwmx", "pwma": return "doc.fill"
        default: return "doc"
        }
    }
}
