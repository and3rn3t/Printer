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
    @State private var uploadPhase: UploadPhase = .idle
    
    enum UploadPhase: Equatable {
        case idle
        case preparing
        case uploading
        case startingPrint
        case complete
        case failed(String)
    }
    
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
                    Section("Upload Progress") {
                        VStack(spacing: 12) {
                            ProgressView(value: uploadProgress)
                                .animation(.easeInOut(duration: 0.3), value: uploadProgress)
                            
                            HStack {
                                phaseIcon
                                Text(phaseDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(uploadProgress * 100))%")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                
                if let error = uploadError {
                    Section {
                        Label {
                            Text(error)
                                .font(.caption)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                        
                        Button("Retry") {
                            sendToPrinter()
                        }
                        .disabled(selectedPrinter == nil)
                    }
                }
            }
            .navigationTitle("Send to Printer")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
    
    // MARK: - Phase Display
    
    private var phaseIcon: some View {
        Group {
            switch uploadPhase {
            case .idle:
                EmptyView()
            case .preparing:
                ProgressView()
                    .controlSize(.small)
            case .uploading:
                Image(systemName: "arrow.up.circle")
                    .foregroundStyle(.blue)
            case .startingPrint:
                ProgressView()
                    .controlSize(.small)
            case .complete:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }
    
    private var phaseDescription: String {
        switch uploadPhase {
        case .idle: return ""
        case .preparing: return "Preparing file..."
        case .uploading: return "Uploading to printer..."
        case .startingPrint: return "Starting print job..."
        case .complete: return "Complete!"
        case .failed(let msg): return msg
        }
    }
    
    // MARK: - Upload
    
    private func sendToPrinter() {
        guard let printer = selectedPrinter else { return }
        
        isUploading = true
        uploadError = nil
        uploadProgress = 0
        uploadPhase = .preparing
        
        Task {
            do {
                // Create print job
                let job = PrintJob(
                    printerName: printer.name,
                    status: .uploading,
                    fileName: "\(model.name).stl",
                    printerIP: printer.ipAddress,
                    jobProtocol: printer.printerProtocol.rawValue
                )
                job.model = model
                model.printJobs.append(job)
                modelContext.insert(job)
                
                // Read file
                let fileURL = model.resolvedFileURL
                
                // Upload to printer with real progress tracking
                let api = AnycubicPrinterAPI()
                
                await MainActor.run {
                    uploadPhase = .uploading
                }
                
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
                    await MainActor.run {
                        uploadPhase = .startingPrint
                    }
                    
                    job.status = .printing
                    job.printStartDate = Date()
                    try await api.startPrint(
                        ipAddress: printer.ipAddress,
                        apiKey: printer.apiKey,
                        filename: "\(model.name).stl",
                        protocol: printer.printerProtocol
                    )
                } else {
                    job.status = .queued
                }
                
                // Update printer connection status
                printer.isConnected = true
                printer.lastConnected = Date()
                
                await MainActor.run {
                    uploadPhase = .complete
                    isUploading = false
                    
                    // Dismiss after brief delay to show completion
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        dismiss()
                    }
                }
                
            } catch {
                await MainActor.run {
                    isUploading = false
                    uploadPhase = .failed(error.localizedDescription)
                    uploadError = error.localizedDescription
                }
            }
        }
    }
}
