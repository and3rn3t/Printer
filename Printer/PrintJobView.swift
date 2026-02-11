//
//  PrintJobView.swift
//  Printer
//
//  Created by Matt on 2/10/26.
//

import SwiftUI
import SwiftData

struct PrintJobView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let model: PrintModel
    let printers: [Printer]
    
    @State private var selectedPrinter: Printer?
    @State private var uploadProgress: Double = 0
    @State private var isUploading = false
    @State private var uploadError: String?
    @State private var startPrintAfterUpload = true
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Select Printer") {
                    if printers.isEmpty {
                        ContentUnavailableView(
                            "No Printers",
                            systemImage: "printer.slash",
                            description: Text("Add a printer in the printer management screen")
                        )
                    } else {
                        Picker("Printer", selection: $selectedPrinter) {
                            Text("Select a printer")
                                .tag(nil as Printer?)
                            
                            ForEach(printers) { printer in
                                HStack {
                                    Image(systemName: printer.isConnected ? "circle.fill" : "circle")
                                        .foregroundStyle(printer.isConnected ? .green : .gray)
                                    Text(printer.name)
                                }
                                .tag(printer as Printer?)
                            }
                        }
                    }
                }
                
                Section("Model") {
                    LabeledContent("Name", value: model.name)
                    LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: model.fileSize, countStyle: .file))
                }
                
                Section {
                    Toggle("Start printing after upload", isOn: $startPrintAfterUpload)
                }
                
                if isUploading {
                    Section {
                        VStack(spacing: 12) {
                            ProgressView(value: uploadProgress)
                            Text("\(Int(uploadProgress * 100))% uploaded")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                if let error = uploadError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Send to Printer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isUploading)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        sendToPrinter()
                    }
                    .disabled(selectedPrinter == nil || isUploading)
                }
            }
        }
    }
    
    private func sendToPrinter() {
        guard let printer = selectedPrinter else { return }
        
        isUploading = true
        uploadError = nil
        
        Task {
            do {
                // Create print job
                let job = PrintJob(printerName: printer.name, status: .uploading)
                job.model = model
                model.printJobs.append(job)
                modelContext.insert(job)
                
                // Read file
                let fileURL = URL(fileURLWithPath: model.fileURL)
                
                // Upload to printer
                let api = AnycubicPrinterAPI()
                
                try await api.uploadFile(
                    ipAddress: printer.ipAddress,
                    apiKey: printer.apiKey,
                    fileURL: fileURL,
                    filename: "\(model.name).stl"
                ) { progress in
                    Task { @MainActor in
                        uploadProgress = progress
                    }
                }
                
                // Start printing if requested
                if startPrintAfterUpload {
                    job.status = .printing
                    try await api.startPrint(
                        ipAddress: printer.ipAddress,
                        apiKey: printer.apiKey,
                        filename: "\(model.name).stl"
                    )
                } else {
                    job.status = .queued
                }
                
                await MainActor.run {
                    isUploading = false
                    dismiss()
                }
                
            } catch {
                await MainActor.run {
                    isUploading = false
                    uploadError = error.localizedDescription
                }
            }
        }
    }
}
