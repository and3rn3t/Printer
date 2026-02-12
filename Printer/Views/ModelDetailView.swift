//
//  ModelDetailView.swift
//  Printer
//
//  Created by Matt on 2/10/26.
//

import SwiftUI
import SwiftData
import OSLog

struct ModelDetailView: View {
    @Bindable var model: PrintModel
    let printers: [Printer]
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PrintModel.name) private var allModels: [PrintModel]

    @AppStorage("showSlicingWarnings") private var showSlicingWarnings = true
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete = true
    
    @State private var showingPrintSheet = false
    @State private var selectedPrinter: Printer?
    @State private var isEditingName = false
    @State private var showingShareSheet = false
    @State private var showingDeleteConfirm = false
    @State private var newTag = ""
    @State private var show3DPreview = false
    @State private var showingCollectionPicker = false
    
    /// All unique tags across the library for auto-suggest
    private var allUniqueTags: [String] {
        Array(Set(allModels.flatMap { $0.tags })).sorted()
    }

    /// Whether this model supports interactive 3D preview
    private var canShow3D: Bool {
        let ext = model.fileURL.components(separatedBy: ".").last?.lowercased() ?? ""
        return ["stl", "obj", "usdz", "usda", "usdc"].contains(ext)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero Thumbnail / 3D Preview Section
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if show3DPreview && canShow3D {
                            Model3DPreviewView(
                                fileURL: model.resolvedFileURL,
                                fileType: model.fileType
                            )
                            .frame(height: 350)
                            .transition(.opacity)
                        } else if let thumbnailData = model.thumbnailData {
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
                    
                    // Source badge + 3D toggle
                    HStack(spacing: 8) {
                        if canShow3D {
                            Button {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    show3DPreview.toggle()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: show3DPreview ? "photo" : "cube")
                                        .font(.caption)
                                    Text(show3DPreview ? "2D" : "3D")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }

                        HStack(spacing: 6) {
                            Image(systemName: model.source.icon)
                                .font(.caption)
                            Text(model.source.displayText)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
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
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .onSubmit {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isEditingName = false
                                }
                                model.modifiedDate = Date()
                            }
                    } else {
                        HStack {
                            Text(model.name)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Spacer()
                            
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isEditingName = true
                                }
                            } label: {
                                Image(systemName: "pencil.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
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

                    // Mesh dimensions
                    if model.hasDimensions {
                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "ruler")
                                    .foregroundStyle(.blue)
                                Text("Dimensions")
                                    .font(.headline)
                            }

                            if let x = model.dimensionX, let y = model.dimensionY, let z = model.dimensionZ {
                                HStack(spacing: 0) {
                                    dimensionPill(label: "W", value: x, color: .red)
                                    Text("×")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 4)
                                    dimensionPill(label: "D", value: y, color: .green)
                                    Text("×")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 4)
                                    dimensionPill(label: "H", value: z, color: .blue)
                                    Spacer()
                                }

                                // Build plate preview against first printer with plate dimensions
                                if let printer = printers.first(where: {
                                    ($0.buildPlateX ?? 0) > 0 && ($0.buildPlateY ?? 0) > 0 && ($0.buildPlateZ ?? 0) > 0
                                }), let bpX = printer.buildPlateX, let bpY = printer.buildPlateY, let bpZ = printer.buildPlateZ {
                                    BuildPlateView(
                                        plateX: bpX,
                                        plateY: bpY,
                                        plateZ: bpZ,
                                        modelX: x,
                                        modelY: y,
                                        modelZ: z,
                                        isResinPrinter: printer.printerProtocol == .act
                                    )
                                    .padding(.top, 4)
                                }
                            }

                            if let verts = model.vertexCount, verts > 0 {
                                InfoRow(
                                    icon: "circle.grid.cross",
                                    label: "Vertices",
                                    value: Self.formatCount(verts)
                                )
                            }

                            if let tris = model.triangleCount, tris > 0 {
                                InfoRow(
                                    icon: "triangle",
                                    label: "Triangles",
                                    value: Self.formatCount(tris)
                                )
                            }
                        }
                    } else if model.fileType.needsSlicing {
                        Divider()

                        Button {
                            Task {
                                let analyzer = MeshAnalyzer()
                                if let info = try? await analyzer.analyze(url: model.resolvedFileURL) {
                                    model.applyMeshInfo(info)
                                }
                            }
                        } label: {
                            Label("Analyze Dimensions", systemImage: "ruler")
                        }
                        .buttonStyle(.bordered)
                    }

                    // Sliced file metadata section
                    if model.hasSlicedMetadata {
                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "layers.3d.top.filled")
                                    .foregroundStyle(.blue)
                                Text("Slice Details")
                                    .font(.headline)
                            }

                            if let layers = model.slicedLayerCount {
                                InfoRow(
                                    icon: "square.stack.3d.up",
                                    label: "Layers",
                                    value: "\(layers)"
                                )
                            }

                            if let layerHeight = model.slicedLayerHeight {
                                InfoRow(
                                    icon: "ruler",
                                    label: "Layer Height",
                                    value: String(format: "%.3f mm", layerHeight)
                                )
                            }

                            if let height = model.slicedPrintHeight, height > 0 {
                                InfoRow(
                                    icon: "arrow.up.and.down",
                                    label: "Print Height",
                                    value: String(format: "%.2f mm", height)
                                )
                            }

                            if let time = model.slicedPrintTimeSeconds, time > 0 {
                                InfoRow(
                                    icon: "clock",
                                    label: "Est. Print Time",
                                    value: formatDuration(Double(time))
                                )
                            }

                            if let volume = model.slicedVolumeMl, volume > 0 {
                                InfoRow(
                                    icon: "drop.fill",
                                    label: "Resin Volume",
                                    value: String(format: "%.1f mL", volume)
                                )
                            }

                            if let exposure = model.slicedExposureTime {
                                InfoRow(
                                    icon: "sun.max.fill",
                                    label: "Exposure",
                                    value: String(format: "%.1f s", exposure)
                                )
                            }

                            if let bottomExposure = model.slicedBottomExposureTime {
                                InfoRow(
                                    icon: "sun.max.trianglebadge.exclamationmark",
                                    label: "Bottom Exposure",
                                    value: String(format: "%.1f s", bottomExposure)
                                )
                            }

                            if let resX = model.slicedResolutionX, let resY = model.slicedResolutionY,
                               resX > 0, resY > 0 {
                                InfoRow(
                                    icon: "rectangle.split.3x3",
                                    label: "Resolution",
                                    value: "\(resX) × \(resY)"
                                )
                            }
                        }
                    } else if model.fileType.isSliced {
                        // Sliced file but no metadata — offer re-parse
                        Divider()

                        Button {
                            Task {
                                let parser = SlicedFileParser()
                                if let metadata = await parser.parseMetadata(from: model.resolvedFileURL) {
                                    model.applyMetadata(metadata)
                                }
                            }
                        } label: {
                            Label("Parse Slice Metadata", systemImage: "arrow.clockwise.circle")
                        }
                        .buttonStyle(.bordered)
                    }

                    Divider()

                    // Favorite toggle
                    HStack {
                        Image(systemName: model.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(model.isFavorite ? .yellow : .gray)
                            .symbolEffect(.bounce, value: model.isFavorite)
                            .contentTransition(.symbolEffect(.replace))
                        Text("Favorite")
                            .font(.headline)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { model.isFavorite },
                            set: { newValue in
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                                    model.isFavorite = newValue
                                }
                            }
                        ))
                            .labelsHidden()
                    }

                    // Tags section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "tag.fill")
                                .foregroundStyle(.blue)
                            Text("Tags")
                                .font(.headline)
                        }

                        if model.tags.isEmpty {
                            Text("No tags — add one below")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            FlowLayoutTags(tags: model.tags) { tag in
                                model.tags.removeAll { $0 == tag }
                            }
                        }

                        TagAutoSuggestField(
                            existingTags: allUniqueTags,
                            newTag: $newTag
                        ) { tag in
                            if !model.tags.contains(tag) {
                                model.tags.append(tag)
                                model.modifiedDate = Date()
                            }
                        }
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
                        Button {
                            showingCollectionPicker = true
                        } label: {
                            HStack {
                                Image(systemName: "folder.badge.plus")
                                Text("Collect")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

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
        .sheet(isPresented: $showingCollectionPicker) {
            AddToCollectionPicker(model: model)
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
            do {
                try await STLFileManager.shared.deleteSTL(at: model.resolvedFileURL.path)
            } catch {
                AppLogger.fileOps.error("Failed to delete model file \(model.name): \(error.localizedDescription)")
            }
        }
        modelContext.delete(model)
    }

    /// Dimension pill view showing axis label + value
    @ViewBuilder
    private func dimensionPill(label: String, value: Float, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(Self.formatDimension(value))
                .font(.callout)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }

    /// Format a dimension in mm, showing appropriate precision
    static func formatDimension(_ value: Float) -> String {
        if value >= 100 {
            return String(format: "%.0f mm", value)
        } else if value >= 10 {
            return String(format: "%.1f mm", value)
        }
        return String(format: "%.2f mm", value)
    }

    /// Format large counts with K/M suffixes
    static func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
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
    
    private var statusIcon: String { job.status.icon }
    private var statusColor: Color { job.status.color }
    private var statusText: String { job.status.displayText }
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
                        withAnimation(.easeInOut(duration: 0.25)) {
                            onRemove(tag)
                        }
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
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
}
