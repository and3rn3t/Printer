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
    @Environment(\.modelContext) private var modelContext

    @AppStorage("showSlicingWarnings") private var showSlicingWarnings = true
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete = true
    
    @State private var showingPrintSheet = false
    @State private var selectedPrinter: Printer?
    @State private var isEditingName = false
    @State private var showingShareSheet = false
    @State private var showingDeleteConfirm = false
    @State private var showingTagEditor = false
    @State private var newTag = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero Thumbnail Section
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let thumbnailData = model.thumbnailData {
#if os(macOS)
                            if let nsImage = NSImage(data: thumbnailData) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            }
#else
                            if let uiImage = UIImage(data: thumbnailData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            }
#endif
                        } else {
                            ZStack {
                                LinearGradient(
                                    colors: [.blue.opacity(0.4), .purple.opacity(0.4)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                
                                VStack(spacing: 12) {
                                    Image(systemName: "cube.transparent")
                                        .font(.system(size: 80))
                                        .foregroundStyle(.white)
                                    
                                    Text("No Preview")
                                        .font(.headline)
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                            }
                            .frame(height: 300)
                        }
                    }
                    .frame(maxHeight: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
                    
                    // Source badge
                    HStack(spacing: 6) {
                        Image(systemName: sourceIcon(for: model.source))
                            .font(.caption)
                        Text(sourceText(for: model.source))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(12)
                }
                .padding(.horizontal)

                // Slicer warning banner
                if model.requiresSlicing && showSlicingWarnings {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Slicing Required")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("This \(model.fileType.displayName) file needs to be sliced before printing on a resin printer. Use a slicer like Anycubic Photon Workshop to generate a .pwmx file.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }
                
                // Model info card
                VStack(spacing: 16) {
                    // Name editing
                    if isEditingName {
                        TextField("Model Name", text: $model.name)
                            .textFieldStyle(.roundedBorder)
                            .font(.title2)
                            .fontWeight(.bold)
                            .onSubmit {
                                isEditingName = false
                                model.modifiedDate = Date()
                            }
                    } else {
                        HStack {
                            Text(model.name)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Spacer()
                            
                            Button {
                                isEditingName = true
                            } label: {
                                Image(systemName: "pencil.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    Divider()
                    
                    // Metadata grid
                    VStack(spacing: 12) {
                        InfoRow(
                            icon: "doc.fill",
                            label: "File Size",
                            value: ByteCountFormatter.string(fromByteCount: model.fileSize, countStyle: .file)
                        )

                        InfoRow(
                            icon: "doc.text.fill",
                            label: "Format",
                            value: model.fileType.displayName
                        )

                        InfoRow(
                            icon: model.requiresSlicing ? "exclamationmark.circle" : "checkmark.seal",
                            label: "Print Ready",
                            value: model.requiresSlicing ? "Needs Slicing" : "Ready"
                        )
                        
                        InfoRow(
                            icon: "calendar",
                            label: "Created",
                            value: model.createdDate.formatted(date: .abbreviated, time: .shortened)
                        )
                        
                        InfoRow(
                            icon: "clock.fill",
                            label: "Modified",
                            value: model.modifiedDate.formatted(date: .abbreviated, time: .shortened)
                        )
                        
                        if !model.printJobs.isEmpty {
                            InfoRow(
                                icon: "printer.fill",
                                label: "Print Jobs",
                                value: "\(model.printJobs.count)"
                            )
                        }
                    }

                    Divider()

                    // Favorite toggle
                    HStack {
                        Image(systemName: model.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(model.isFavorite ? .yellow : .gray)
                        Text("Favorite")
                            .font(.headline)
                        Spacer()
                        Toggle("", isOn: $model.isFavorite)
                            .labelsHidden()
                    }

                    // Tags section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "tag.fill")
                                .foregroundStyle(.blue)
                            Text("Tags")
                                .font(.headline)
                            Spacer()
                            Button {
                                showingTagEditor = true
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }

                        if model.tags.isEmpty {
                            Text("No tags — tap + to add")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            FlowLayoutTags(tags: model.tags) { tag in
                                model.tags.removeAll { $0 == tag }
                            }
                        }
                    }
                    .alert("Add Tag", isPresented: $showingTagEditor) {
                        TextField("Tag name", text: $newTag)
                        Button("Add") {
                            let trimmed = newTag.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty && !model.tags.contains(trimmed) {
                                model.tags.append(trimmed)
                                model.modifiedDate = Date()
                            }
                            newTag = ""
                        }
                        Button("Cancel", role: .cancel) { newTag = "" }
                    }
                    
                    Divider()
                    
                    // Notes section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "note.text")
                                .foregroundStyle(.blue)
                            Text("Notes")
                                .font(.headline)
                        }
                        
                        TextEditor(text: $model.notes)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(Color.gray.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .onChange(of: model.notes) { _, _ in
                                model.modifiedDate = Date()
                            }
                    }
                }
                .padding()
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.background)
                        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
                }
                .padding(.horizontal)
                
                // Print history
                if !model.printJobs.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(.blue)
                            Text("Print History")
                                .font(.headline)
                        }
                        .padding(.horizontal)
                        
                        VStack(spacing: 12) {
                            ForEach(model.printJobs) { job in
                                PrintJobRowView(job: job)
                            }
                        }
                    }
                    .padding()
                    .background {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.background)
                            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
                    }
                    .padding(.horizontal)
                }
                
                // Action button
                VStack(spacing: 12) {
                    Button {
                        showingPrintSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "printer.fill")
                                .font(.headline)
                            Text("Send to Printer")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(printers.isEmpty ? Color.gray : Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: printers.isEmpty ? .clear : .blue.opacity(0.3), radius: 8, y: 4)
                    }
                    .disabled(printers.isEmpty)
                    
                    if printers.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .font(.caption)
                            Text("Add a printer to start printing")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }

                    // File management actions
                    HStack(spacing: 16) {
                        ShareLink(item: model.resolvedFileURL) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Export")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        Button(role: .destructive) {
                            if confirmBeforeDelete {
                                showingDeleteConfirm = true
                            } else {
                                deleteModel()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .foregroundStyle(.red)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .padding(.vertical)
        }
        .navigationTitle(model.name)
#if os(macOS)
        .navigationSubtitle("\(ByteCountFormatter.string(fromByteCount: model.fileSize, countStyle: .file))")
#endif
        .sheet(isPresented: $showingPrintSheet) {
            PrintJobView(model: model, printers: printers)
        }
        .alert("Delete Model", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { deleteModel() }
        } message: {
            Text("Are you sure you want to delete \"\(model.name)\"? The file will be permanently removed.")
        }
    }

    private func deleteModel() {
        Task {
            try? await STLFileManager.shared.deleteSTL(at: model.resolvedFileURL.path)
        }
        modelContext.delete(model)
    }
    
    private func sourceIcon(for source: ModelSource) -> String {
        switch source {
        case .scanned: return "camera.fill"
        case .imported: return "square.and.arrow.down.fill"
        case .downloaded: return "arrow.down.circle.fill"
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

// MARK: - Info Row Component

struct InfoRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Label {
                Text(label)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
            }
            
            Spacer()
            
            Text(value)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Print Job Row

struct PrintJobRowView: View {
    let job: PrintJob
    
    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 44, height: 44)
                
                Image(systemName: statusIcon)
                    .font(.headline)
                    .foregroundStyle(statusColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(job.printerName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack(spacing: 6) {
                    Text(job.startDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if job.effectiveDuration > 0 {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        HStack(spacing: 2) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text(job.formattedDuration)
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Status badge
            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(statusColor.opacity(0.15))
                .foregroundStyle(statusColor)
                .clipShape(Capsule())
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.15))
        }
    }
    
    private var statusIcon: String {
        switch job.status {
        case .preparing: return "clock.fill"
        case .uploading: return "arrow.up.circle.fill"
        case .queued: return "tray.fill"
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

// MARK: - Flow Layout for Tags

struct FlowLayoutTags: View {
    let tags: [String]
    let onRemove: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Text(tag)
                        .font(.caption)
                    Button {
                        onRemove(tag)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.blue.opacity(0.1))
                .foregroundStyle(.blue)
                .clipShape(Capsule())
            }
        }
    }
}

// Note: FlowLayout is defined in PrintablesDetailView.swift and shared across views
