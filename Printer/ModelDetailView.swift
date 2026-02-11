//
//  ModelDetailView.swift
//  Printer
//
//  Created by Matt on 2/10/26.
//

import SwiftUI
import SwiftData

struct ModelDetailView: View {
    @Bindable var model: PrintModel
    let printers: [Printer]
    
    @State private var showingPrintSheet = false
    @State private var selectedPrinter: Printer?
    @State private var isEditingName = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Thumbnail
                if let thumbnailData = model.thumbnailData {
#if os(macOS)
                    if let nsImage = NSImage(data: thumbnailData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
#else
                    if let uiImage = UIImage(data: thumbnailData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
#endif
                } else {
                    Image(systemName: "cube")
                        .font(.system(size: 100))
                        .foregroundStyle(.secondary)
                        .frame(height: 200)
                }
                
                // Model info
                VStack(spacing: 12) {
                    // Name
                    if isEditingName {
                        TextField("Model Name", text: $model.name)
                            .textFieldStyle(.roundedBorder)
                            .font(.title2)
                            .onSubmit {
                                isEditingName = false
                                model.modifiedDate = Date()
                            }
                    } else {
                        HStack {
                            Text(model.name)
                                .font(.title2)
                                .bold()
                            
                            Button {
                                isEditingName = true
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    Divider()
                    
                    // Metadata
                    LabeledContent("File Size") {
                        Text(ByteCountFormatter.string(fromByteCount: model.fileSize, countStyle: .file))
                    }
                    
                    LabeledContent("Source") {
                        HStack {
                            Image(systemName: sourceIcon(for: model.source))
                            Text(sourceText(for: model.source))
                        }
                    }
                    
                    LabeledContent("Created") {
                        Text(model.createdDate.formatted(date: .abbreviated, time: .shortened))
                    }
                    
                    LabeledContent("Modified") {
                        Text(model.modifiedDate.formatted(date: .abbreviated, time: .shortened))
                    }
                    
                    Divider()
                    
                    // Notes
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.headline)
                        
                        TextEditor(text: $model.notes)
                            .frame(minHeight: 100)
                            .border(Color.secondary.opacity(0.2))
                            .onChange(of: model.notes) { _, _ in
                                model.modifiedDate = Date()
                            }
                    }
                }
                .padding()
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.background)
                        .shadow(radius: 2)
                }
                
                // Print history
                if !model.printJobs.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Print History")
                            .font(.headline)
                        
                        ForEach(model.printJobs) { job in
                            PrintJobRowView(job: job)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.background)
                            .shadow(radius: 2)
                    }
                }
                
                // Print button
                Button {
                    showingPrintSheet = true
                } label: {
                    Label("Send to Printer", systemImage: "printer.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(printers.isEmpty)
                
                if printers.isEmpty {
                    Text("Add a printer to start printing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle(model.name)
#if os(macOS)
        .navigationSubtitle("\(ByteCountFormatter.string(fromByteCount: model.fileSize, countStyle: .file))")
#endif
        .sheet(isPresented: $showingPrintSheet) {
            PrintJobView(model: model, printers: printers)
        }
    }
    
    private func sourceIcon(for source: ModelSource) -> String {
        switch source {
        case .scanned: return "camera.fill"
        case .imported: return "square.and.arrow.down"
        case .downloaded: return "arrow.down.circle"
        }
    }
    
    private func sourceText(for source: ModelSource) -> String {
        switch source {
        case .scanned: return "Scanned"
        case .imported: return "Imported"
        case .downloaded: return "Downloaded"
        }
    }
}

// MARK: - Print Job Row

struct PrintJobRowView: View {
    let job: PrintJob
    
    var body: some View {
        HStack {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(job.printerName)
                    .font(.subheadline)
                
                Text(job.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(statusText)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.2))
                .clipShape(Capsule())
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.background.secondary)
        }
    }
    
    private var statusIcon: String {
        switch job.status {
        case .preparing: return "clock"
        case .uploading: return "arrow.up.circle"
        case .queued: return "tray"
        case .printing: return "printer.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "xmark.circle"
        }
    }
    
    private var statusColor: Color {
        switch job.status {
        case .preparing, .uploading, .queued: return .orange
        case .printing: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }
    
    private var statusText: String {
        switch job.status {
        case .preparing: return "Preparing"
        case .uploading: return "Uploading"
        case .queued: return "Queued"
        case .printing: return "Printing"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}
