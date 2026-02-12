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
    
    @AppStorage("defaultPrinterID") private var defaultPrinterID: String = ""
    
    @State private var selectedPrinter: Printer?
    @State private var uploadProgress: Double = 0
    @State private var isUploading = false
    @State private var uploadError: String?
    @State private var startPrintAfterUpload = true
    @State private var uploadPhase: UploadPhase = .idle
    /// For ACT printers, the user must specify the filename as it exists on the printer's USB
    @State private var actFilename: String = ""
    @Query(sort: \ResinProfile.name) private var resinProfiles: [ResinProfile]
    @State private var selectedResinProfile: ResinProfile?
    
    enum UploadPhase: Equatable {
        case idle
        case preparing
        case uploading
        case startingPrint
        case complete
        case failed(String)
    }
    
    /// Whether the selected printer uses ACT protocol (resin printers with no HTTP upload)
    private var isACTPrinter: Bool {
        selectedPrinter?.printerProtocol == .act
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
                    
                    if let printer = selectedPrinter {
                        LabeledContent("Protocol") {
                            Text(printer.printerProtocol == .act ? "ACT (TCP)" : "OctoPrint (HTTP)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Material profile selection
                if !resinProfiles.isEmpty {
                    Section("Material") {
                        Picker("Resin Profile", selection: $selectedResinProfile) {
                            Text("None").tag(nil as ResinProfile?)
                            ForEach(resinProfiles) { profile in
                                HStack {
                                    Circle()
                                        .fill(Color(hex: profile.colorHex) ?? .gray)
                                        .frame(width: 12, height: 12)
                                    Text(profile.name)
                                }
                                .tag(profile as ResinProfile?)
                            }
                        }

                        if let profile = selectedResinProfile, profile.costPerMl > 0,
                           let volume = model.slicedVolumeMl, volume > 0 {
                            let cost = Double(volume) * profile.costPerMl
                            LabeledContent("Material Cost") {
                                Text(cost, format: .currency(code: UserDefaults.standard.string(forKey: "resinCurrency") ?? "USD"))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }

                // Print estimate from sliced metadata
                if model.hasSlicedMetadata {
                    Section("Print Estimate") {
                        if let time = model.slicedPrintTimeSeconds, time > 0 {
                            LabeledContent("Estimated Time") {
                                Text(formatDuration(Double(time)))
                                    .fontWeight(.medium)
                            }
                        }

                        if let layers = model.slicedLayerCount, layers > 0 {
                            LabeledContent("Layers", value: "\(layers)")
                        }

                        if let volume = model.slicedVolumeMl, volume > 0 {
                            LabeledContent("Resin Volume") {
                                Text(String(format: "%.1f mL", volume))
                            }
                        }

                        if let volume = model.slicedVolumeMl, volume > 0 {
                            let costPerMl = UserDefaults.standard.double(forKey: "resinCostPerMl")
                            if costPerMl > 0 {
                                let cost = Double(volume) * costPerMl
                                let currency = UserDefaults.standard.string(forKey: "resinCurrency") ?? "USD"
                                LabeledContent("Estimated Cost") {
                                    Text(Self.formatCost(cost, currency: currency))
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.blue)
                                }
                            }
                        }

                        if let height = model.slicedPrintHeight, height > 0 {
                            LabeledContent("Print Height") {
                                Text(String(format: "%.1f mm", height))
                            }
                        }

                        if let layerH = model.slicedLayerHeight, layerH > 0 {
                            LabeledContent("Layer Height") {
                                Text(String(format: "%.3f mm", layerH))
                            }
                        }

                        if let exposure = model.slicedExposureTime, exposure > 0 {
                            LabeledContent("Exposure", value: String(format: "%.1fs", exposure))
                        }
                    }
                } else if !model.fileType.isSliced {
                    Section {
                        Label {
                            Text("No print estimate available — this file has not been sliced. Slice it in your slicer software to see time, layer, and cost estimates.")
                                .font(.caption)
                        } icon: {
                            Image(systemName: "info.circle")
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                // Model dimensions
                if model.hasDimensions, let x = model.dimensionX, let y = model.dimensionY, let z = model.dimensionZ {
                    Section("Model Dimensions") {
                        LabeledContent("Size") {
                            Text(String(format: "%.1f × %.1f × %.1f mm", x, y, z))
                                .fontWeight(.medium)
                        }

                        // Build plate fit check
                        if let printer = selectedPrinter {
                            let bpX = printer.buildPlateX ?? 0
                            let bpY = printer.buildPlateY ?? 0
                            let bpZ = printer.buildPlateZ ?? 0
                            if bpX > 0 && bpY > 0 && bpZ > 0 {
                                let fits = x <= bpX && y <= bpY && z <= bpZ
                                HStack {
                                    Image(systemName: fits ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                        .foregroundStyle(fits ? .green : .orange)
                                    Text(fits ? "Fits on build plate" : "May exceed build plate")
                                        .font(.subheadline)
                                    Spacer()
                                    Text(String(format: "%.0f × %.0f × %.0f mm", bpX, bpY, bpZ))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                
                // ACT printer: file must already be on USB
                if isACTPrinter {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Resin Printer (ACT Protocol)", systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                            
                            Text("This printer uses the ACT protocol. Files cannot be uploaded over the network — they must be copied to USB manually. Enter the filename as it appears on the printer's USB drive to start printing.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        TextField("Filename on USB (e.g. model.pwmx)", text: $actFilename)
                            #if os(iOS)
                            .textContentType(.none)
                            #endif
                    } header: {
                        Text("Print File")
                    }
                } else {
                    Section {
                        Toggle("Start printing after upload", isOn: $startPrintAfterUpload)
                    }
                }
                
                if isUploading {
                    Section("Progress") {
                        VStack(spacing: 12) {
                            ProgressView(value: uploadProgress)
                                .animation(.easeInOut(duration: 0.3), value: uploadProgress)
                            
                            HStack {
                                phaseIcon
                                Text(phaseDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if !isACTPrinter {
                                    Text("\(Int(uploadProgress * 100))%")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .monospacedDigit()
                                }
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
                    Button(isACTPrinter ? "Print" : "Send") {
                        sendToPrinter()
                    }
                    .disabled(sendButtonDisabled)
                }
            }
            .onAppear {
                preselectDefaultPrinter()
            }
        }
    }
    
    /// Whether the send/print button should be disabled
    private var sendButtonDisabled: Bool {
        if selectedPrinter == nil || isUploading { return true }
        if isACTPrinter && actFilename.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        return false
    }
    
    /// Pre-select the default printer from settings if available
    private func preselectDefaultPrinter() {
        guard selectedPrinter == nil, !defaultPrinterID.isEmpty else { return }
        selectedPrinter = printers.first { $0.id.uuidString == defaultPrinterID }
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
    
    private static func formatCost(_ cost: Double, currency: String) -> String {
        let symbol: String
        switch currency {
        case "EUR": symbol = "\u{20AC}"
        case "GBP": symbol = "\u{00A3}"
        case "JPY": symbol = "\u{00A5}"
        case "CAD": symbol = "CA$"
        case "AUD": symbol = "A$"
        default: symbol = "$"
        }
        return "\(symbol)\(String(format: "%.2f", cost))"
    }

    private func sendToPrinter() {
        guard let printer = selectedPrinter else { return }
        
        isUploading = true
        uploadError = nil
        uploadProgress = 0
        uploadPhase = .preparing
        
        Task {
            // Create print job record
            let fileName = isACTPrinter ? actFilename : "\(model.name).stl"
            let job = PrintJob(
                printerName: printer.name,
                status: isACTPrinter ? .printing : .uploading,
                fileName: fileName,
                printerIP: printer.ipAddress,
                jobProtocol: printer.printerProtocol.rawValue
            )
            job.model = model
            job.resinProfile = selectedResinProfile
            model.printJobs.append(job)
            modelContext.insert(job)
            
            do {
                if isACTPrinter {
                    // ACT protocol — send goprint command directly (file must be on USB)
                    await MainActor.run {
                        uploadPhase = .startingPrint
                        uploadProgress = 0.5
                    }
                    
                    let api = AnycubicPrinterAPI()
                    try await api.startPrint(
                        ipAddress: printer.ipAddress,
                        apiKey: printer.apiKey,
                        filename: actFilename.trimmingCharacters(in: .whitespaces),
                        protocol: printer.printerProtocol
                    )
                    
                    job.status = .printing
                    job.printStartDate = Date()
                    
                } else {
                    // HTTP protocol — upload file then optionally start print
                    let fileURL = model.resolvedFileURL
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
                }
                
                // Update printer connection status
                printer.isConnected = true
                printer.lastConnected = Date()
                
                await MainActor.run {
                    uploadPhase = .complete
                    uploadProgress = 1.0
                    isUploading = false
                    
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        dismiss()
                    }
                }
                
            } catch {
                // Rollback: mark the job as failed instead of leaving it in uploading state
                job.status = .failed
                job.endDate = Date()
                
                await MainActor.run {
                    isUploading = false
                    uploadPhase = .failed(error.localizedDescription)
                    uploadError = error.localizedDescription
                }
            }
        }
    }
}
